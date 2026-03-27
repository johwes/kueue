# Module 01: Kueue Basics

Learn core Kueue concepts through hands-on demos: ResourceFlavors, ClusterQueues, LocalQueues, fair sharing, and workload management.

## Prerequisites

**Required:**
- OpenShift cluster with cluster-admin access
- Module 00 (Operator installation) complete
- `oc` CLI installed

**Time:** ~30 minutes

---

## Module Overview

This module demonstrates how Kueue solves the fundamental GPU sharing challenge between ML training and inference workloads through:

1. **Resource Configuration** (00-setup) - Set up the foundation
2. **Fair Sharing Demos** (01-demo-fair-sharing) - Run training workloads
3. **Priority Demos** (02-demo-priorities) - Run production workloads

---

## The Resource Allocation Challenge

Your organization has invested in GPU infrastructure for ML workloads. The challenge: **How do you allocate these expensive resources fairly between two competing needs?**

### ML Training (Experimentation)
- **Needs**: Large resource bursts for model training
- **Pattern**: Unpredictable, bursty workload
- **Tolerance**: Can wait in queue during busy periods
- **Priority**: Lower (innovation vs. production)

### ML Inference (Production)
- **Needs**: Guaranteed resources for customer SLAs
- **Pattern**: Predictable, scheduled batch jobs
- **Tolerance**: Cannot be starved of resources
- **Priority**: Higher (production-critical)

---

## What You'll Learn

By completing this module, you will understand:

✅ How Kueue manages resources through ResourceFlavors and ClusterQueues
✅ How to create LocalQueues for different ML workload types
✅ How jobs are queued and admitted based on available resources
✅ How to prevent production workload starvation in a shared cluster
✅ How fair sharing works between competing teams

---

## Module Structure

### [00-setup](./00-setup/) - Resource Configuration

Configure the foundation for Kueue resource management:
- ResourceFlavors (define resource types)
- ClusterQueue (total resource pool)
- LocalQueues (separate queues for training vs. inference)

**Go here first** to set up your cluster.

### [01-demo-fair-sharing](./01-demo-fair-sharing/) - Training Workloads

Run ML training experiments to see queueing and fair sharing in action:
- ResNet model training
- LLM fine-tuning
- Hyperparameter tuning

These demos show how Kueue manages competing training workloads.

### [02-demo-priorities](./02-demo-priorities/) - Production Workloads

Run production inference workloads to see priority handling:
- Batch customer inference
- Model validation
- Feature extraction

These demos show how production workloads get guaranteed access.

---

## Quick Start

```bash
cd 01-kueue-basics

# Step 1: Set up resources
cd 00-setup
oc apply -f .

# Step 2: Run training demos
cd ../01-demo-fair-sharing
oc apply -f jobs/

# Step 3: Monitor fair sharing
oc get workload -n ml-training

# Step 4: Run production demos
cd ../02-demo-priorities
oc apply -f jobs/

# Step 5: See both teams sharing resources
oc get workload -n ml-training -n ml-inference
```

---

## Architecture

```
ResourceFlavor (default-flavor)
         ↓
ClusterQueue (cluster-total)
    ├── Total: 5 CPUs, 2Gi memory
    │   (In production: GPUs would be managed here)
    │
    ├──→ LocalQueue (ml-training-queue)
    │    └── Namespace: ml-training
    │         Purpose: Model training, experiments
    │         Can tolerate queueing
    │
    └──→ LocalQueue (ml-inference-queue)
         └── Namespace: ml-inference
              Purpose: Production batch inference
              Needs guaranteed access
```

**Note:** This demo uses CPU resources for portability. In production, you'd configure GPU ResourceFlavors (e.g., `nvidia.com/gpu`) using the same Kueue patterns.

---

## The Problem Without Kueue

**Before implementing Kueue**, sharing GPU resources leads to conflicts:

1. **Resource Starvation**: Training jobs consume all GPUs, blocking production inference
2. **SLA Breaches**: Production delayed, customers experience degraded service
3. **Manual Intervention**: Engineers manually kill training jobs to free resources
4. **Wasted Resources**: GPUs sit idle after manual kills, then saturated when training resumes
5. **Team Friction**: Training team vs. Inference team conflicts over resource priority

---

## The Solution With Kueue

**After implementing Kueue**, resource sharing becomes automatic:

1. **Fair Queueing**: Training and inference workloads share resources fairly
2. **Production Priority**: Inference workloads get admitted even when training saturates cluster
3. **Efficient Utilization**: Training uses idle capacity without blocking production
4. **Visibility**: Teams can see queue depth and admission status
5. **Automatic**: No manual intervention required

---

## Key Concepts

### ResourceFlavor
Represents a type of resource in your cluster (e.g., GPUs, high-memory nodes, specific zones).

### ClusterQueue
Defines the total pool of resources available for sharing. Sets quota limits and preemption policies.

### LocalQueue
Namespace-scoped queue that maps to a ClusterQueue. Teams submit jobs to their LocalQueue.

### Workload
Automatic object created by Kueue for each Job to manage admission. You never create this manually.

---

## Next Steps

1. **Start with setup:** Go to [00-setup](./00-setup/) to configure your cluster
2. **Run demos:** Follow the demos in order (01, then 02)
3. **Learn monitoring:** After completing this module, proceed to [Module 02: Borrowing & Preemption](../02-borrowing-preemption/)

---

## Additional Resources

- [Kueue Resource Concepts](https://kueue.sigs.k8s.io/docs/concepts/)
- [ClusterQueue Configuration](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/)
- [ResourceFlavor Documentation](https://kueue.sigs.k8s.io/docs/concepts/resource_flavor/)
- [Red Hat Build of Kueue Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/)
