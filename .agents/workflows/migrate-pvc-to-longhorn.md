---
description: How to migrate an application's PersistentVolumeClaim (PVC) to Longhorn
---

This workflow describes the process of safely migrating an existing application's configuration or data from an old PVC to a new Longhorn-backed PVC.

## 1. Create the new Longhorn PVC

First, create a new PVC manifest (e.g., `longhorn-config-pvc.yaml`) in the application's persistence directory. Set the `storageClassName` to `longhorn` and specify the desired capacity.

**IMPORTANT: The storage size for the new PVC must be explicitly specified by the USER. If the USER does not specify a size, you MUST ask them what size it should be before proceeding.**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <app-name>-config-longhorn-pvc
  namespace: <namespace>
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: <USER_SPECIFIED_SIZE> # e.g., 4Gi
  storageClassName: longhorn
  volumeMode: Filesystem
```

Add this new file to the respective `kustomization.yaml` resources list and apply it to the cluster to provision the volume:

```bash
kubectl apply -k apps/path/to/app/persistence
```

## 2. Scale down the application

To prevent data corruption during the transfer, scale the deployment or statefulset down to 0 replicas.

```bash
kubectl scale deployment <app-name> -n <namespace> --replicas=0
```

## 3. Create a temporary migration pod

Run a temporary `alpine` pod that mounts both the old PVC and the new Longhorn PVC.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: <app-name>-migration-pv-copy
  namespace: <namespace>
spec:
  restartPolicy: Never
  containers:
  - name: copier
    image: alpine:latest
    command: ["/bin/sh", "-c"]
    args:
      - "echo 'Starting migration...'; cp -av /source/. /dest/; echo 'Migration complete!'"
    volumeMounts:
    - name: source-vol
      mountPath: /source
      readOnly: true
    - name: dest-vol
      mountPath: /dest
  volumes:
  - name: source-vol
    persistentVolumeClaim:
      claimName: <old-pvc-name>
  - name: dest-vol
    persistentVolumeClaim:
      claimName: <new-longhorn-pvc-name>
EOF
```

## 4. Monitor and verify the transfer

Watch the pod start and view its logs to ensure the copy process completes successfully.

```bash
kubectl logs -f <app-name>-migration-pv-copy -n <namespace>
```

## 5. Clean up

Once the logs show 'Migration complete!', delete the temporary pod.

```bash
kubectl delete pod <app-name>-migration-pv-copy -n <namespace>
```

## 6. Update the Deployment

Update the application's `deployment.yaml` or `statefulset.yaml` to change the corresponding volume's `claimName` to the new Longhorn PVC name `<new-longhorn-pvc-name>`.

## 7. Apply the updated deployment manifest and scale up

Apply the updated deployment manifest using `kubectl apply -k` to the cluster. This will automatically restore the application to its original replica count (or you can manually scale it up if needed).

```bash
kubectl apply -k apps/path/to/app
# If necessary, manually scale up:
kubectl scale deployment <app-name> -n <namespace> --replicas=1
```

Verify the application is running and the data is intact.
