# Module 01: Resource Borrowing & Preemption

This module solves the ultimate cluster admin challenge: **How do I keep my GPUs 100% utilized without making the Production team wait?**

## Prerequisites

**Required:**
- OpenShift cluster with cluster-admin access
- Module 00 (Operator installation) complete
- `oc` CLI installed

**Note:** This module is self-contained and creates its own ClusterQueues and LocalQueues. You do NOT need to complete Module 01 (01-kueue-basics) first. This module will use the same namespaces (`ml-training`, `ml-inference`) but will replace the basic ClusterQueues with cohort-based ones.

**Time:** ~30 minutes

---


This module solves the ultimate cluster admin challenge: **How do I keep my GPUs 100% utilized without making the Production team wait?**

## The Problem: Wasted Resources vs. Production SLAs

Your organization has invested in 10 GPUs for ML workloads. You need to allocate them between two teams:

### Traditional Approach (Hard Partitioning)

```
Training Team: 6 GPUs (fixed allocation)
Inference Team: 4 GPUs (fixed allocation)
```

**The Problem:**
- **Training GPUs idle 60% of the time** (nights, weekends, between experiments)
- **Inference needs more GPUs during peak hours** (9 AM - 5 PM customer traffic)
- **Total utilization: ~52%** (6 GPUs × 40% + 4 GPUs × 100%)
- **Wasted capacity: 3.6 GPUs sitting idle** on average

**Business Impact:**
- $100,000+ in unused GPU capacity per year
- Slow experiment iteration (training could use 10 GPUs but limited to 6)
- Inability to scale inference during peak demand

---

## The Solution: Cohorts + Borrowing + Preemption

Kueue provides three mechanisms that work together:

### 1. **Cohorts** (Resource-Sharing Club)
A Cohort is a group of ClusterQueues that can share resources with each other.

```
Cohort: "ml-gpu-pool"
  ├── ClusterQueue: training-cluster-queue (6 GPUs nominal)
  └── ClusterQueue: inference-cluster-queue (4 GPUs nominal)

Total: 10 GPUs available for dynamic sharing
```

### 2. **Borrowing** (Use Idle Capacity)
When Inference's GPUs are idle, Training can **borrow** them temporarily.

**Example: Night Training**
```
Time: 2 AM
- Inference: Using 0 GPUs (no customer traffic)
- Training: Can borrow all 4 inference GPUs
- Training runs with: 6 (own) + 4 (borrowed) = 10 GPUs
- Utilization: 100%!
```

### 3. **Preemption** (Reclaim Resources)
When Inference needs resources back, it can **preempt** (evict) Training jobs.

**Example: Business Hours**
```
Time: 9 AM
- Training: Using 10 GPUs (6 own + 4 borrowed)
- Inference: Needs 4 GPUs for customer requests
- Action: Training job using borrowed resources is PREEMPTED
- Training checkpoints progress and waits
- Inference gets its 4 GPUs immediately
```

**Result:**
- ✅ **95%+ GPU utilization** (vs. 52% with hard partitioning)
- ✅ **Production SLAs met** (inference always gets resources)
- ✅ **Faster experiments** (training uses idle capacity)
- ✅ **$80,000+ saved annually** (better resource utilization)

---

## Module Structure

This module demonstrates borrowing and preemption through hands-on demos:

### [00-setup](./00-setup/README.md)
**Configure Resource Sharing**

Create the foundation for borrowing and preemption:
- Cohort definition (the "resource-sharing club")
- Two ClusterQueues (training vs. inference)
- WorkloadPriorityClasses (high vs. low priority)
- Checkpoint storage (PVC for resumable jobs)

### [01-demo-borrowing](./01-demo-borrowing/README.md)
**Demo 1: Borrowing in Action**

Watch Training borrow idle Inference resources:
- Training submits job needing 5 CPUs (more than its 3 CPU quota)
- Inference's 2 CPUs are idle
- Training **borrows** 2 CPUs from Inference
- Job runs successfully with 5 CPUs total

### [02-demo-preemption-checkpoint](./02-demo-preemption-checkpoint/README.md)
**Demo 2: Preemption with Resume**

See production workloads reclaim resources:
- Low-priority Training job uses borrowed resources
- High-priority Inference job arrives (needs resources NOW)
- Training job is **preempted** (evicted)
- Training **checkpoints** its progress (saves state to PVC)
- After Inference completes, Training **resumes** from checkpoint
- No work lost!

### [03-best-practices](./03-best-practices/README.md)
**Production Guidelines**

Learn how to design production-ready configurations:
- Checkpoint frequency strategies
- Priority class design patterns
- Borrowing policies (when to allow, when to restrict)
- Monitoring preemption rates
- Cost optimization techniques

---

## Prerequisites

Before starting this module:

1. **Complete Module 01 (01-kueue-basics) & 02** - You need to understand:
   - ResourceFlavors and ClusterQueues
   - LocalQueues and workload admission
   - Fair sharing basics

2. **Cluster Requirements:**
   - Red Hat Build of Kueue installed
   - Two namespaces: `ml-training`, `ml-inference`
   - Dynamic PVC provisioning available

3. **Time Commitment:**
   - Setup: 10 minutes
   - Demo 1 (Borrowing): 5 minutes
   - Demo 2 (Preemption): 10 minutes
   - Total: ~25 minutes

---

## Key Concepts Introduced

| Concept | What It Is | Why It Matters |
|---------|-----------|----------------|
| **Cohort** | Group of ClusterQueues that share resources | Enables borrowing between teams |
| **Borrowing** | Temporarily using another queue's idle quota | Maximizes cluster utilization (95%+ vs. 52%) |
| **Preemption** | Evicting lower-priority jobs to reclaim resources | Guarantees production SLAs |
| **WorkloadPriorityClass** | Defines job importance (VIP vs. Economy) | Controls which jobs can be preempted |
| **Checkpointing** | Saving job state before eviction | Enables resume without losing progress |

---

## Learning Objectives

By the end of this module, you will:

✅ **Understand Cohorts** - How ClusterQueues form resource-sharing clubs

✅ **Configure Borrowing** - Allow teams to use each other's idle capacity

✅ **Set Job Priorities** - Define which workloads are production-critical

✅ **Implement Preemption** - Enable high-priority jobs to reclaim resources

✅ **Build Resumable Jobs** - Use checkpointing to survive preemption

✅ **Optimize Costs** - Achieve 95%+ utilization while meeting SLAs

---

## Real-World Impact

**Before Kueue (Hard Partitioning):**
```
Training: 6 GPUs × 40% utilization = 2.4 GPUs used
Inference: 4 GPUs × 100% utilization = 4.0 GPUs used
Total: 6.4 / 10 GPUs = 64% utilization
Wasted: 3.6 GPUs idle
Cost: $36,000/year wasted (at $10k/GPU/year)
```

**After Kueue (Borrowing + Preemption):**
```
Off-peak: Training uses 10 GPUs (6 own + 4 borrowed)
Peak hours: Inference uses 4 GPUs (training returns borrowed)
Total: 9.5 / 10 GPUs = 95% utilization
Wasted: 0.5 GPUs idle
Cost: $5,000/year wasted
Savings: $31,000/year
```

**With 100 GPUs:** Savings scale to $310,000/year!

---

## Next Steps

Ready to maximize your cluster utilization? Start with [00-setup](./00-setup/README.md)!

---

## Additional Resources

- [Kueue Cohorts Documentation](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/#cohort)
- [Preemption Policies](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/#preemption)
- [WorkloadPriorityClass](https://kueue.sigs.k8s.io/docs/concepts/workload_priority_class/)
- [Red Hat Build of Kueue - Advanced Features](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/)
