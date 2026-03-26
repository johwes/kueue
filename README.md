# Kueue on OpenShift - Learning Path

A hands-on demo and learning path for Red Hat Build of Kueue on OpenShift, solving real-world resource sharing challenges in ML/AI workloads.

## The Challenge: Shared GPU Economics

In traditional software development, organizations run separate clusters for Dev, Test, and Production environments. This works well because CPU and memory resources are relatively affordable.

**However, AI/ML workloads change this equation:**

- **GPU infrastructure is extremely expensive** (10-100x the cost of CPU nodes)
- **Separate GPU clusters are economically prohibitive** for most organizations
- **All ML workloads must share the same GPU resources**: experimentation, training, and production inference

This creates a critical challenge: **How do you fairly share expensive GPU resources between competing workload types without starving production workloads or blocking innovation?**

## What is Kueue?

Kueue is a Kubernetes-native job queueing and scheduling framework that solves this multi-tenancy challenge by providing:
- **Fair resource sharing** across different ML workload types
- **Quota management** to prevent any workload type from monopolizing GPUs
- **Priority-based scheduling** to ensure production SLAs are met
- **Intelligent queueing** to maximize GPU utilization while preventing starvation

## Real-World Scenario

This demo simulates a common situation in organizations running ML workloads on OpenShift:

### **ML Training Team** (Experimentation & Research)
- Running model training experiments
- Hyperparameter tuning jobs
- Fine-tuning foundation models
- Variable duration (hours to days)
- Can tolerate queueing delays
- Unpredictable, bursty workload patterns

### **ML Inference Team** (Production Services)
- Batch inference for customer requests
- Model serving preparation
- Time-sensitive with SLAs
- Requires guaranteed resource availability
- Predictable, scheduled workload patterns

### **The Problem Without Kueue:**
- Training jobs consume all GPUs at random times
- Production inference workloads are starved of resources
- SLA breaches occur, impacting customers
- No visibility into queue depth or wait times
- Manual intervention required to kill training jobs

### **The Solution With Kueue:**
- Production inference gets priority and guaranteed quota
- Training jobs use idle capacity without blocking production
- Fair queueing ensures all teams get their share
- Transparent visibility into resource allocation
- Automatic workload admission based on available resources

## Learning Objectives

By completing this demo, you will understand:
1. How Kueue manages GPU resources through ResourceFlavors and ClusterQueues
2. How to create LocalQueues for different ML workload types with different priorities
3. How jobs are queued and admitted based on available resources
4. How to prevent production workload starvation in a shared cluster
5. How to monitor queue status and troubleshoot resource contention

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  ClusterQueue: "gpu-cluster-total"                      │
│  - Total GPU pool available for ML workloads            │
│  - Sets quotas for training vs inference                │
│  - Enforces fair sharing policies                       │
└────────────────┬────────────────────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────────┐  ┌───▼─────────────┐
│ LocalQueue       │  │ LocalQueue      │
│ (ml-training)    │  │ (ml-inference)  │
│                  │  │                 │
│ For:             │  │ For:            │
│ - Experiments    │  │ - Production    │
│ - Fine-tuning    │  │ - Batch jobs    │
│ - Research       │  │ - SLA-critical  │
└──────┬───────────┘  └────┬────────────┘
       │                   │
   ┌───▼────┐         ┌────▼────┐
   │Training│         │Inference│
   │  Jobs  │         │  Jobs   │
   └────────┘         └─────────┘
```

## Prerequisites

- OpenShift cluster with cluster-admin access
- `oc` CLI installed and configured
- Red Hat Build of Kueue operator installed (covered in 00-setup)

**Note:** While this demo focuses on the GPU sharing use case, the same Kueue patterns apply to CPU-only workloads. For simplicity, this demo uses CPU resources that can run on any OpenShift cluster.

## Learning Path

Follow these modules in order:

### [00-setup](./00-setup/README.md)
**The Problem & The Solution** - Understand the GPU sharing challenge and install the Red Hat Build of Kueue operator.

### [01-resource-configuration](./01-resource-configuration/README.md)
**Resource Management Setup** - Create ResourceFlavors, ClusterQueues, and LocalQueues to allocate resources between ML training and inference workloads.

### [02-workload-kueue-basics](./02-workload-kueue-basics/README.md)
**Kueue Basics - Workload Submission** - Submit realistic ML training and inference jobs to observe queue admission, fair sharing, and priority handling.

### [03-monitoring](./03-monitoring/README.md)
**Observability & Success Metrics** - Monitor queues, track resource utilization, and verify that production workloads are never starved.

## Quick Start

```bash
# 1. Install Kueue operator
cd 00-setup
./install.sh

# 2. Create resource configuration for ML workloads
cd ../01-resource-configuration
oc apply -f .

# 3. Submit ML training and inference workloads
cd ../02-workload-kueue-basics
oc apply -f ml-training/
oc apply -f ml-inference/

# 4. Monitor fair resource sharing
cd ../03-monitoring
./monitor.sh
```

## What You'll Learn

By the end of this demo, you'll see:
- ✅ Production inference jobs get guaranteed resources
- ✅ Training experiments use idle capacity without blocking production
- ✅ Fair queueing prevents resource starvation
- ✅ Transparent visibility into workload admission
- ✅ How to solve the GPU sharing challenge at scale

## References

- [Red Hat Build of Kueue Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/1.0/)
- [Kueue Upstream Documentation](https://kueue.sigs.k8s.io/docs/)
- [OpenShift Joining Kueue Blog](https://www.redhat.com/en/blog/openshift-joining-kueue)
- [Behind the Queues: How Kueue Reimagines Scheduling](https://www.redhat.com/en/blog/behind-queues-how-kueue-reimagines-scheduling-red-hat-openshift)

## License

Apache 2.0
