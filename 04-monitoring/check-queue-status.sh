#!/bin/bash

# Health check for Kueue queues and workloads

set -e

echo "======================================"
echo "Kueue Health Check"
echo "======================================"
echo "Timestamp: $(date)"
echo ""

# Check ClusterQueues
echo "Checking ClusterQueues..."
if oc get clusterqueue cluster-total &>/dev/null; then
    echo "✓ ClusterQueue 'cluster-total' exists"

    # Check if active
    ACTIVE=$(oc get clusterqueue cluster-total -o jsonpath='{.status.conditions[?(@.type=="Active")].status}')
    if [ "$ACTIVE" == "True" ]; then
        echo "✓ ClusterQueue is active"
    else
        echo "✗ ClusterQueue is not active"
    fi

    # Get resource usage
    echo ""
    echo "Resource Usage:"
    oc get clusterqueue cluster-total -o json | jq -r '
        .status.flavorsReservation[0].resources[] |
        "  \(.name): \(.used // "0") / \(.total)"
    '

    # Get workload counts
    PENDING=$(oc get clusterqueue cluster-total -o jsonpath='{.status.pendingWorkloads}')
    ADMITTED=$(oc get clusterqueue cluster-total -o jsonpath='{.status.admittedWorkloads}')
    echo ""
    echo "Workload Status:"
    echo "  Pending: ${PENDING:-0}"
    echo "  Admitted: ${ADMITTED:-0}"
else
    echo "✗ ClusterQueue 'cluster-total' not found"
fi

echo ""
echo "Checking LocalQueues..."

# Check ml-training queue
if oc get localqueue ml-training-queue -n ml-training &>/dev/null; then
    echo "✓ LocalQueue 'ml-training-queue' exists"

    ACTIVE=$(oc get localqueue ml-training-queue -n ml-training -o jsonpath='{.status.conditions[?(@.type=="Active")].status}')
    if [ "$ACTIVE" == "True" ]; then
        echo "  ✓ LocalQueue is active"
    else
        echo "  ✗ LocalQueue is not active"
    fi
else
    echo "✗ LocalQueue 'ml-training-queue' not found in ml-training namespace"
fi

# Check ml-inference queue
if oc get localqueue ml-inference-queue -n ml-inference &>/dev/null; then
    echo "✓ LocalQueue 'ml-inference-queue' exists"

    ACTIVE=$(oc get localqueue ml-inference-queue -n ml-inference -o jsonpath='{.status.conditions[?(@.type=="Active")].status}')
    if [ "$ACTIVE" == "True" ]; then
        echo "  ✓ LocalQueue is active"
    else
        echo "  ✗ LocalQueue is not active"
    fi
else
    echo "✗ LocalQueue 'ml-inference-queue' not found in ml-inference namespace"
fi

echo ""
echo "Checking for pending workloads..."

# Check for pending workloads
PENDING_ALPHA=$(oc get workload -n ml-training -o json 2>/dev/null | jq -r '[.items[] | select(.status.admission == null)] | length')
PENDING_BETA=$(oc get workload -n ml-inference -o json 2>/dev/null | jq -r '[.items[] | select(.status.admission == null)] | length')

if [ "$PENDING_ALPHA" -gt 0 ]; then
    echo "⚠ ML Training has $PENDING_ALPHA pending workload(s)"
    echo "  Reasons:"
    oc get workload -n ml-training -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.admission == null) |
        "  - \(.metadata.name): \(.status.conditions[]? | select(.type=="Admitted") | .message // "Unknown")"
    ' || echo "  Unable to retrieve reasons"
else
    echo "✓ ML Training has no pending workloads"
fi

if [ "$PENDING_BETA" -gt 0 ]; then
    echo "⚠ ML Inference has $PENDING_BETA pending workload(s)"
    echo "  Reasons:"
    oc get workload -n ml-inference -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.admission == null) |
        "  - \(.metadata.name): \(.status.conditions[]? | select(.type=="Admitted") | .message // "Unknown")"
    ' || echo "  Unable to retrieve reasons"
else
    echo "✓ ML Inference has no pending workloads"
fi

echo ""
echo "======================================"
echo "Health Check Complete"
echo "======================================"
