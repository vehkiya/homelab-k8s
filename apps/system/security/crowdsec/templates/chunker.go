package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	chunkSize = 9500
	listsDir  = "/tmp/www/lists"
	v4URL     = "http://127.0.0.1:41412/security/blocklist.txt?ipv4only"
	v6URL     = "http://127.0.0.1:41412/security/blocklist.txt?ipv6only"
)

var httpClient = &http.Client{
	Timeout: 15 * time.Second,
}

func initFiles() {
	if err := os.MkdirAll(listsDir, 0755); err != nil {
		log.Printf("[chunker] Failed to create lists directory: %v", err)
	}
	initialFiles := []string{"ipv4-0.txt", "ipv4-1.txt", "ipv4-2.txt", "ipv6-0.txt"}
	header := []byte("# CrowdSec EDL shard (initializing)\n")
	for _, fn := range initialFiles {
		fp := filepath.Join(listsDir, fn)
		if _, err := os.Stat(fp); os.IsNotExist(err) {
			if err := os.WriteFile(fp, header, 0644); err != nil {
				log.Printf("[chunker] Failed to initialize %s: %v", fn, err)
			}
		}
	}
}

func fetchIPs(url string) ([]string, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "CrowdSec-EDL-Chunker/1.0")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %d from %s", resp.StatusCode, url)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	raw := string(body)
	seen := make(map[string]struct{})
	var entries []string

	lines := strings.Split(raw, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if _, exists := seen[line]; !exists {
			seen[line] = struct{}{}
			entries = append(entries, line)
		}
	}

	sort.Strings(entries)
	return entries, nil
}

func updateShards(family string, items []string, minShards int) error {
	var chunks [][]string
	for i := 0; i < len(items); i += chunkSize {
		end := i + chunkSize
		if end > len(items) {
			end = len(items)
		}
		chunks = append(chunks, items[i:end])
	}

	numShards := len(chunks)
	if numShards < minShards {
		numShards = minShards
	}

	for idx := 0; idx < numShards; idx++ {
		var shardItems []string
		if idx < len(chunks) {
			shardItems = chunks[idx]
		}

		filename := fmt.Sprintf("%s-%d.txt", family, idx)
		targetPath := filepath.Join(listsDir, filename)
		tempPath := filepath.Join(listsDir, fmt.Sprintf(".%s.tmp", filename))

		var builder strings.Builder
		builder.WriteString(fmt.Sprintf("# CrowdSec EDL shard (count: %d)\n", len(shardItems)))
		for _, item := range shardItems {
			builder.WriteString(item)
			builder.WriteByte('\n')
		}

		if err := os.WriteFile(tempPath, []byte(builder.String()), 0644); err != nil {
			return fmt.Errorf("failed to write temp shard %s: %w", tempPath, err)
		}

		if err := os.Rename(tempPath, targetPath); err != nil {
			return fmt.Errorf("failed to rename temp shard to %s: %w", targetPath, err)
		}
	}

	return nil
}

func syncLists() error {
	v4Items, err := fetchIPs(v4URL)
	if err != nil {
		return fmt.Errorf("fetching IPv4: %w", err)
	}

	v6Items, err := fetchIPs(v6URL)
	if err != nil {
		return fmt.Errorf("fetching IPv6: %w", err)
	}

	if err := updateShards("ipv4", v4Items, 3); err != nil {
		return fmt.Errorf("updating IPv4 shards: %w", err)
	}

	if err := updateShards("ipv6", v6Items, 1); err != nil {
		return fmt.Errorf("updating IPv6 shards: %w", err)
	}

	log.Printf("[chunker] Sync succeeded: %d IPv4 entries, %d IPv6 entries", len(v4Items), len(v6Items))
	return nil
}

func backgroundSync() {
	log.Println("[chunker] Starting background sync goroutine...")
	initialSyncDone := false
	for {
		err := syncLists()
		if err != nil {
			if !initialSyncDone {
				log.Printf("[chunker] Waiting for mirror on 127.0.0.1:41412: %v", err)
				time.Sleep(2 * time.Second)
			} else {
				log.Printf("[chunker] Sync error: %v", err)
				time.Sleep(60 * time.Second)
			}
			continue
		}

		initialSyncDone = true
		time.Sleep(60 * time.Second)
	}
}

func handleLists(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	filename := strings.TrimPrefix(r.URL.Path, "/lists/")
	if filename == "" || strings.Contains(filename, "/") || strings.Contains(filename, "\\") || strings.Contains(filename, "..") {
		http.Error(w, "Invalid filename", http.StatusBadRequest)
		return
	}

	targetPath := filepath.Join(listsDir, filename)
	data, err := os.ReadFile(targetPath)
	if err != nil {
		if os.IsNotExist(err) {
			http.Error(w, "File Not Found", http.StatusNotFound)
		} else {
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		}
		return
	}

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Content-Length", fmt.Sprintf("%d", len(data)))
	w.WriteHeader(http.StatusOK)
	if r.Method != http.MethodHead {
		_, _ = w.Write(data)
	}
}

func handleHealthz(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}
	body := []byte("ok\n")
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Content-Length", fmt.Sprintf("%d", len(body)))
	w.WriteHeader(http.StatusOK)
	if r.Method != http.MethodHead {
		_, _ = w.Write(body)
	}
}

func main() {
	initFiles()
	go backgroundSync()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", handleHealthz)
	mux.HandleFunc("/lists/", handleLists)

	server := &http.Server{
		Addr:              ":8080",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("[chunker] Serving EDL on :8080")
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("[chunker] Server error: %v", err)
	}
}
