echo "WARNING: This is only used in case of dump upgrades"
echo "Must provide PATH to .dump file in ENV"


MEILI_HOST='https://meilisearch.kerrlab.app'
MEILI_API_KEY="$(kubectl get secret meilisearch-kubernetes-master-key -o jsonpath='{.data.MEILI_MASTER_KEY}' | base64 --decode)"

echo "Current version of meilisearch is:"
curl -X GET "$MEILI_HOST/version" -H "Authorization: Bearer $MEILI_API_KEY"
echo "\n"
echo "Creating database dumps"
dump_uid=$(curl \
  -X POST "$MEILI_HOST/dumps" \
  -H "Authorization: Bearer $MEILI_API_KEY" | jq '.taskUid')
  
echo "dump_uid is $dump_uid" 
  
curl \
    -X GET "$MEILI_HOST/dumps/$dump_uid/status" \
    -H "Authorization: Bearer $MEILI_API_KEY"
    
kubectl exec meilisearch-kubernetes-0 -- cp -R data.ms data.ms.backup
kubectl exec meilisearch-kubernetes-0 -- rm -r data.ms

