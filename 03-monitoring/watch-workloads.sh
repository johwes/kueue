#!/bin/bash

# Watch workload lifecycle with detailed status
# Usage: ./watch-workloads.sh [namespace]

NAMESPACE=${1:-"-A"}

if [ "$NAMESPACE" == "-A" ]; then
    echo "Watching workloads in all namespaces..."
    echo "Press Ctrl+C to exit"
    echo ""
else
    echo "Watching workloads in namespace: $NAMESPACE..."
    echo "Press Ctrl+C to exit"
    echo ""
fi

# Header
printf "%-50s %-15s %-10s %-15s %-20s\n" "NAME" "NAMESPACE" "ADMITTED" "QUEUE" "AGE"
echo "========================================================================================="

# Watch loop
while true; do
    if [ "$NAMESPACE" == "-A" ]; then
        oc get workload -A -o json 2>/dev/null | jq -r '
            .items[] |
            {
                name: .metadata.name,
                namespace: .metadata.namespace,
                admitted: (if .status.admission != null then "Yes" else "No" end),
                queue: (.metadata.labels["kueue.x-k8s.io/queue-name"] // "N/A"),
                age: .metadata.creationTimestamp
            } |
            "\(.name) \(.namespace) \(.admitted) \(.queue) \(.age)"
        ' | while read name namespace admitted queue age; do
            # Calculate age (simplified - shows timestamp for now)
            printf "%-50s %-15s %-10s %-15s %-20s\n" "$name" "$namespace" "$admitted" "$queue" "$age"
        done
    else
        oc get workload -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
            .items[] |
            {
                name: .metadata.name,
                namespace: .metadata.namespace,
                admitted: (if .status.admission != null then "Yes" else "No" end),
                queue: (.metadata.labels["kueue.x-k8s.io/queue-name"] // "N/A"),
                age: .metadata.creationTimestamp
            } |
            "\(.name) \(.namespace) \(.admitted) \(.queue) \(.age)"
        ' | while read name namespace admitted queue age; do
            printf "%-50s %-15s %-10s %-15s %-20s\n" "$name" "$namespace" "$admitted" "$queue" "$age"
        done
    fi

    sleep 5
    # Clear for next iteration (optional)
    # clear
    # printf "%-50s %-15s %-10s %-15s %-20s\n" "NAME" "NAMESPACE" "ADMITTED" "QUEUE" "AGE"
    # echo "========================================================================================="
done
