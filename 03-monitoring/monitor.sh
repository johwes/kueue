#!/bin/bash

# Real-time Kueue monitoring dashboard
# Displays ClusterQueues, LocalQueues, and Workloads

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

while true; do
    clear
    echo "======================================"
    echo "Kueue Monitoring Dashboard"
    echo "======================================"
    echo "Refreshed: $(date)"
    echo ""

    echo -e "${BLUE}=== ClusterQueues ===${NC}"
    echo ""
    oc get clusterqueue 2>/dev/null || echo "No ClusterQueues found or permission denied"
    echo ""

    echo -e "${BLUE}=== ClusterQueue Details (cluster-total) ===${NC}"
    echo ""
    oc get clusterqueue cluster-total -o json 2>/dev/null | jq -r '
        {
            name: .metadata.name,
            pendingWorkloads: .status.pendingWorkloads,
            admittedWorkloads: .status.admittedWorkloads,
            resources: .status.flavorsReservation[0].resources
        }
    ' 2>/dev/null || echo "Unable to retrieve ClusterQueue details"
    echo ""

    echo -e "${BLUE}=== LocalQueues ===${NC}"
    echo ""
    oc get localqueue -A 2>/dev/null || echo "No LocalQueues found or permission denied"
    echo ""

    echo -e "${BLUE}=== Workloads by Namespace ===${NC}"
    echo ""
    echo "Team Alpha:"
    oc get workload -n team-alpha 2>/dev/null | head -10 || echo "  No workloads or namespace not found"
    echo ""
    echo "Team Beta:"
    oc get workload -n team-beta 2>/dev/null | head -10 || echo "  No workloads or namespace not found"
    echo ""

    echo -e "${BLUE}=== Recent Jobs ===${NC}"
    echo ""
    echo "Team Alpha:"
    oc get jobs -n team-alpha 2>/dev/null | head -10 || echo "  No jobs or namespace not found"
    echo ""
    echo "Team Beta:"
    oc get jobs -n team-beta 2>/dev/null | head -10 || echo "  No jobs or namespace not found"
    echo ""

    echo -e "${YELLOW}Press Ctrl+C to exit${NC}"

    sleep 5
done
