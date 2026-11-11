// sync-inventory prints the ArgoCD app inventory derived from the
// ApplicationSets in apps/gitops/app-of-apps, and with --check verifies
// that .context/ still matches the repository.
//
//	go run .context/sync-inventory.go          # inventory tables
//	go run .context/sync-inventory.go --check  # drift check, exit 1 on drift
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const (
	appSetDir  = "apps/gitops/app-of-apps"
	contextDir = ".context"
	maxLines   = 150
)

// status values
const (
	deployed = "deployed"
	excluded = "excluded" // matched by a generator glob but excluded
	shared   = "shared"   // kustomize layer consumed by other apps, no Application
)

type app struct {
	Name, Path, AppSet, Namespace, Status string
	Auto, Helm                            bool
	Waves                                 map[string]bool
	Kinds                                 map[string]int
}

// kind -> contract label, in display order
var contracts = []struct{ kind, label string }{
	{"HTTPRoute", "HTTPRoute"},
	{"IngressRoute", "IngressRoute"},
	{"Gateway", "Gateway"},
	{"Middleware", "Middleware"},
	{"SecurityPolicy", "SecPol"},
	{"BackendTrafficPolicy", "BTP"},
	{"HTTPScaledObject", "KEDA-HTTP"},
	{"CiliumNetworkPolicy", "CNP"},
	{"CiliumClusterwideNetworkPolicy", "CCNP"},
	{"ExternalSecret", "ExtSecret"},
	{"ClusterSecretStore", "SecretStore"},
	{"PersistentVolumeClaim", "PVC"},
	{"PersistentVolume", "PV"},
	{"StorageClass", "StorageClass"},
	{"ServiceMonitor", "SvcMon"},
	{"PodMonitor", "PodMon"},
	{"PrometheusRule", "PromRule"},
	{"CronJob", "CronJob"},
}

var (
	kindRe    = regexp.MustCompile(`^kind:\s*(\w+)`)
	waveRe    = regexp.MustCompile(`argocd\.argoproj\.io/sync-wave:\s*"?(-?\d+)"?`)
	nsRe      = regexp.MustCompile(`^namespace:\s*"?([\w-]+)"?`)
	kvRe      = regexp.MustCompile(`^(\s*)(- )?(\w+):\s*"?([^"#]*?)"?\s*$`)
	pathTokRe = regexp.MustCompile("(?:apps|infra|\\.github|\\.context)/[\\w./-]*[\\w/]")
	digestRe  = regexp.MustCompile(`sha256:[0-9a-f]{12,}`)
	tagRe     = regexp.MustCompile(`[\w/-]:v?\d+\.\d+\.\d+`)
)

func main() {
	check := len(os.Args) > 1 && os.Args[1] == "--check"
	if _, err := os.Stat(appSetDir); err != nil {
		fatal("run from the repository root: %v", err)
	}
	apps := discover()
	for _, a := range apps {
		scan(a)
	}
	if check {
		os.Exit(runCheck(apps))
	}
	printInventory(apps)
}

func fatal(f string, a ...any) {
	fmt.Fprintf(os.Stderr, "ERROR: "+f+"\n", a...)
	os.Exit(2)
}

// discover resolves every ApplicationSet generator to app directories.
func discover() []*app {
	files, _ := filepath.Glob(filepath.Join(appSetDir, "*.yaml"))
	sort.Strings(files)
	var apps []*app
	claimed := map[string]bool{}
	for _, f := range files {
		for _, a := range parseAppSet(f) {
			apps = append(apps, a)
			claimed[a.Path] = true
		}
	}
	// kustomize layers under apps/ that no generator claims
	filepath.WalkDir("apps", func(p string, d os.DirEntry, err error) error {
		if err != nil || !d.IsDir() {
			return nil
		}
		if _, err := os.Stat(filepath.Join(p, "kustomization.yaml")); err != nil {
			return nil
		}
		for c := range claimed {
			if p == c || strings.HasPrefix(p, c+"/") || strings.HasPrefix(c, p+"/") {
				return nil
			}
		}
		if p == appSetDir {
			return nil
		}
		apps = append(apps, &app{Name: filepath.Base(p), Path: p, AppSet: "-", Namespace: "-", Status: shared})
		return filepath.SkipDir
	})
	return apps
}

type item map[string]string

// parseAppSet reads the regular subset of YAML the ApplicationSets use.
func parseAppSet(file string) []*app {
	fh, err := os.Open(file)
	if err != nil {
		fatal("%v", err)
	}
	defer fh.Close()

	var (
		setName, destNS, section string
		auto, inDest             bool
		dirs, elems              []item
		cur                      item
	)
	flush := func() {
		if cur == nil {
			return
		}
		if section == "directories" {
			dirs = append(dirs, cur)
		} else if section == "elements" {
			elems = append(elems, cur)
		}
		cur = nil
	}
	sc := bufio.NewScanner(fh)
	for sc.Scan() {
		line := sc.Text()
		trim := strings.TrimSpace(line)
		if trim == "" || strings.HasPrefix(trim, "#") {
			continue
		}
		switch trim {
		case "directories:", "elements:":
			flush()
			section = strings.TrimSuffix(trim, ":")
			continue
		case "template:":
			flush()
			section = "template"
			continue
		case "destination:":
			inDest = true
			continue
		case "automated:":
			auto = true
			continue
		}
		m := kvRe.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		indent, dash, key, val := len(m[1]), m[2] != "", m[3], m[4]
		switch {
		case setName == "" && indent == 2 && key == "name":
			setName = val
		case section == "directories" || section == "elements":
			if dash {
				flush()
				cur = item{}
			}
			if cur != nil {
				cur[key] = val
			}
		case inDest && key == "namespace":
			destNS, inDest = val, false
		}
	}
	flush()

	var out []*app
	mk := func(name, path, status string) *app {
		ns := destNS
		if strings.Contains(ns, "path.basename") {
			ns = filepath.Base(path)
		}
		return &app{Name: name, Path: path, AppSet: setName, Namespace: ns, Status: status, Auto: auto}
	}
	excl := map[string]bool{}
	for _, d := range dirs {
		if d["exclude"] == "true" {
			matches, _ := filepath.Glob(d["path"])
			for _, m := range matches {
				excl[m] = true
			}
		}
	}
	for _, d := range dirs {
		if d["exclude"] == "true" {
			continue
		}
		matches, _ := filepath.Glob(d["path"])
		sort.Strings(matches)
		for _, m := range matches {
			if st, err := os.Stat(m); err != nil || !st.IsDir() {
				continue
			}
			status := deployed
			if excl[m] {
				status = excluded
			}
			out = append(out, mk(filepath.Base(m), m, status))
		}
	}
	for _, e := range elems {
		out = append(out, mk(e["name"], e["path"], deployed))
	}
	return out
}

// scan collects kinds, sync-waves and helm usage from an app directory and
// from any relative kustomize bases it pulls in.
func scan(a *app) {
	a.Kinds, a.Waves = map[string]int{}, map[string]bool{}
	seen := map[string]bool{}
	var walk func(dir string)
	walk = func(dir string) {
		dir = filepath.Clean(dir)
		if seen[dir] {
			return
		}
		seen[dir] = true
		filepath.WalkDir(dir, func(p string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			if ext := filepath.Ext(p); ext != ".yaml" && ext != ".yml" {
				return nil
			}
			isKust := filepath.Base(p) == "kustomization.yaml"
			fh, err := os.Open(p)
			if err != nil {
				return nil
			}
			defer fh.Close()
			sc := bufio.NewScanner(fh)
			sc.Buffer(make([]byte, 1024*1024), 16*1024*1024)
			for sc.Scan() {
				line := sc.Text()
				if m := kindRe.FindStringSubmatch(line); m != nil {
					a.Kinds[m[1]]++
				}
				if m := waveRe.FindStringSubmatch(line); m != nil {
					a.Waves[m[1]] = true
				}
				if !isKust {
					continue
				}
				if strings.HasPrefix(line, "helmCharts:") {
					a.Helm = true
				}
				if m := nsRe.FindStringSubmatch(line); m != nil && filepath.Dir(p) == a.Path {
					a.Namespace = m[1]
				}
				if t := strings.TrimSpace(line); strings.HasPrefix(t, "- ../") {
					ref := filepath.Join(filepath.Dir(p), strings.TrimPrefix(t, "- "))
					if st, err := os.Stat(ref); err == nil && st.IsDir() {
						walk(ref)
					}
				}
			}
			return nil
		})
	}
	walk(a.Path)
}

func (a *app) contracts() string {
	var out []string
	if a.Helm {
		out = append(out, "Helm")
	}
	for _, c := range contracts {
		if a.Kinds[c.kind] > 0 {
			out = append(out, c.label)
		}
	}
	if len(out) == 0 {
		return "-"
	}
	return strings.Join(out, ", ")
}

func (a *app) waves() string {
	if len(a.Waves) == 0 {
		return "-"
	}
	var w []string
	for k := range a.Waves {
		w = append(w, k)
	}
	sort.Strings(w)
	return strings.Join(w, ",")
}

func printInventory(apps []*app) {
	groups := map[string][]*app{}
	var order []string
	for _, a := range apps {
		key := a.AppSet
		if a.Status == shared {
			key = "(shared layers, no Application)"
		}
		if _, ok := groups[key]; !ok {
			order = append(order, key)
		}
		groups[key] = append(groups[key], a)
	}
	n := 0
	for _, g := range order {
		sync := "manual sync"
		if groups[g][0].Auto {
			sync = "automated"
		}
		if strings.HasPrefix(g, "(") {
			fmt.Printf("\n## %s\n\n", g)
		} else {
			fmt.Printf("\n## ApplicationSet %s (%s)\n\n", g, sync)
		}
		fmt.Println("| App | Path | Namespace | Wave | Contracts | Status |")
		fmt.Println("|---|---|---|---|---|---|")
		for _, a := range groups[g] {
			fmt.Printf("| %s | `%s` | %s | %s | %s | %s |\n", a.Name, a.Path, a.Namespace, a.waves(), a.contracts(), a.Status)
			n++
		}
	}
	fmt.Printf("\nTotal: %d entries\n", n)
}

func runCheck(apps []*app) int {
	var problems []string
	domainFiles, _ := filepath.Glob(filepath.Join(contextDir, "domains", "*.md"))
	var domains strings.Builder
	for _, f := range domainFiles {
		b, _ := os.ReadFile(f)
		domains.Write(b)
		domains.WriteByte('\n')
	}
	text := domains.String()
	for _, a := range apps {
		re := regexp.MustCompile(regexp.QuoteMeta(a.Path) + `(?:[^\w/-]|$)`)
		if !re.MatchString(text) {
			problems = append(problems, fmt.Sprintf("not indexed: %s (%s, appset %s) -> add `%s` to a .context/domains/*.md table", a.Name, a.Status, a.AppSet, a.Path))
		}
	}

	var all []string
	filepath.WalkDir(contextDir, func(p string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() && filepath.Ext(p) == ".md" {
			all = append(all, p)
		}
		return nil
	})
	sort.Strings(all)
	for _, f := range all {
		b, _ := os.ReadFile(f)
		lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
		if len(lines) >= maxLines {
			problems = append(problems, fmt.Sprintf("too long: %s has %d lines (limit <%d)", f, len(lines), maxLines))
		}
		missing := map[string]bool{}
		for i, l := range lines {
			for _, tok := range pathTokRe.FindAllString(l, -1) {
				tok = strings.TrimRight(tok, "/")
				if _, err := os.Stat(tok); err != nil && !missing[tok] {
					missing[tok] = true
					problems = append(problems, fmt.Sprintf("stale path: %s:%d references %s, which does not exist", f, i+1, tok))
				}
			}
			if digestRe.MatchString(l) || tagRe.MatchString(l) {
				problems = append(problems, fmt.Sprintf("volatile data: %s:%d looks like an image tag or digest", f, i+1))
			}
		}
	}

	if len(problems) > 0 {
		for _, p := range problems {
			fmt.Println("DRIFT: " + p)
		}
		fmt.Printf("FAIL: %d problem(s)\n", len(problems))
		return 1
	}
	fmt.Printf("OK: All %d apps are indexed in .context/domains/*.md\n", len(apps))
	return 0
}
