kubectl -n argo port-forward deployment/argo-server 2746:2746 &
kubectl port-forward statefulsets/postgres 5432:5432 &
kubectl port-forward deployments/localstack 4566:4566 &
kubectl port-forward deployments/superset 8088:8088 &

echo "Press CTRL-C to stop port forwarding and exit the script"
wait
