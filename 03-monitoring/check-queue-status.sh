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

# Check team-alpha queue
if oc get localqueue team-alpha-queue -n team-alpha &>/dev/null; then
    echo "✓ LocalQueue 'team-alpha-queue' exists"

    ACTIVE=$(oc get localqueue team-alpha-queue -n team-alpha -o jsonpath='{.status.conditions[?(@.type=="Active")].status}')
    if [ "$ACTIVE" == "True" ]; then
        echo "  ✓ LocalQueue is active"
    else
        echo "  ✗ LocalQueue is not active"
    fi
else
    echo "✗ LocalQueue 'team-alpha-queue' not found in team-alpha namespace"
fi

# Check team-beta queue
if oc get localqueue team-beta-queue -n team-beta &>/dev/null; then
    echo "✓ LocalQueue 'team-beta-queue' exists"

    ACTIVE=$(oc get localqueue team-beta-queue -n team-beta -o jsonpath='{.status.conditions[?(@.type=="Active")].status}')
    if [ "$ACTIVE" == "True" ]; then
        echo "  ✓ LocalQueue is active"
    else
        echo "  ✗ LocalQueue is not active"
    fi
else
    echo "✗ LocalQueue 'team-beta-queue' not found in team-beta namespace"
fi

echo ""
echo "Checking for pending workloads..."

# Check for pending workloads
PENDING_ALPHA=$(oc get workload -n team-alpha -o json 2>/dev/null | jq -r '[.items[] | select(.status.admission == null)] | length')
PENDING_BETA=$(oc get workload -n team-beta -o json 2>/dev/null | jq -r '[.items[] | select(.status.admission == null)] | length')

if [ "$PENDING_ALPHA" -gt 0 ]; then
    echo "⚠ Team Alpha has $PENDING_ALPHA pending workload(s)"
    echo "  Reasons:"
    oc get workload -n team-alpha -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.admission == null) |
        "  - \(.metadata.name): \(.status.conditions[]? | select(.type=="Admitted") | .message // "Unknown")"
    ' || echo "  Unable to retrieve reasons"
else
    echo "✓ Team Alpha has no pending workloads"
fi

if [ "$PENDING_BETA" -gt 0 ]; then
    echo "⚠ Team Beta has $PENDING_BETA pending workload(s)"
    echo "  Reasons:"
    oc get workload -n team-beta -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.admission == null) |
        "  - \(.metadata.name): \(.status.conditions[]? | select(.type=="Admitted") | .message // "Unknown")"
    ' || echo "  Unable to retrieve reasons"
else
    echo "✓ Team Beta has no pending workloads"
fi

echo ""
echo "======================================"
echo "Health Check Complete"
echo "======================================"
