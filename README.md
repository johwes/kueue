# Kueue on OpenShift - Learning Path

A hands-on demo and learning path for Red Hat Build of Kueue on OpenShift, demonstrating fair resource sharing and job queueing across multiple teams.

## What is Kueue?

Kueue is a Kubernetes-native job queueing and scheduling framework that enables:
- **Fair resource sharing** across teams and tenants
- **Quota management** to prevent resource monopolization
- **Priority-based scheduling** for critical workloads
- **Optimized cluster utilization** through intelligent queueing

## Learning Objectives

By completing this demo, you will understand:
1. How Kueue manages resources through ResourceFlavors and ClusterQueues
2. How to create LocalQueues for different teams with different quotas
3. How jobs are admitted based on available resources
4. How to monitor queue status and workload admission
5. How priority affects job scheduling

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│  ClusterQueue (cluster-scoped)                      │
│  - Defines pools of resources                       │
│  - Sets quota limits                                │
│  - References ResourceFlavors                       │
└────────────────┬────────────────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────┐  ┌──────▼────────┐
│ LocalQueue   │  │ LocalQueue    │
│ (team-alpha) │  │ (team-beta)   │
│ namespace-   │  │ namespace-    │
│ scoped       │  │ scoped        │
└──────┬───────┘  └───────┬───────┘
       │                  │
   ┌───▼────┐        ┌────▼───┐
   │ Jobs   │        │ Jobs   │
   └────────┘        └────────┘
```

## Prerequisites

- OpenShift cluster with cluster-admin access
- `oc` CLI installed and configured
- Red Hat Build of Kueue operator installed (covered in 00-setup)

## Demo Scenario

This demo simulates two development teams sharing an OpenShift cluster:
- **team-alpha**: Data processing team with higher resource allocation
- **team-beta**: Testing team with lower resource allocation

We'll demonstrate:
- Jobs queueing when resources are exhausted
- Fair resource distribution between teams
- Priority-based admission
- Workload lifecycle management

## Learning Path

Follow these modules in order:

### [00-setup](./00-setup/README.md)
Install and configure the Red Hat Build of Kueue operator on OpenShift.

### [01-resource-configuration](./01-resource-configuration/README.md)
Create ResourceFlavors, ClusterQueues, and LocalQueues to establish resource management.

### [02-workloads](./02-workloads/README.md)
Submit sample jobs and observe queue admission and resource allocation.

### [03-monitoring](./03-monitoring/README.md)
Learn how to monitor queues, workloads, and troubleshoot common issues.

## Quick Start

```bash
# 1. Install Kueue operator
cd 00-setup
./install.sh

# 2. Create resource configuration
cd ../01-resource-configuration
oc apply -f .

# 3. Submit sample workloads
cd ../02-workloads
oc apply -f team-alpha/
oc apply -f team-beta/

# 4. Monitor workloads
cd ../03-monitoring
./monitor.sh
```

## References

- [Red Hat Build of Kueue Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/1.0/)
- [Kueue Upstream Documentation](https://kueue.sigs.k8s.io/docs/)
- [OpenShift Joining Kueue Blog](https://www.redhat.com/en/blog/openshift-joining-kueue)
- [Behind the Queues: How Kueue Reimagines Scheduling](https://www.redhat.com/en/blog/behind-queues-how-kueue-reimagines-scheduling-red-hat-openshift)

## License

Apache 2.0
