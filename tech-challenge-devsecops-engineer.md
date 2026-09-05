# DevSecOps Engineer — Technical Assessment

## Overview

For the technical assessment, we'd like you to build a small, working, secured deployment of a trivial web application on a Kubernetes cluster — and then talk us through the decisions you made along the way.

The application itself is deliberately uninteresting: a static "hello world" page served by nginx. Everything we care about sits around it — how the image is built, how it ships, who can reach it, whether the image has security vulnerabilities.

You'll have **5 calendar days** to complete this, followed by a **showcase and technical discussion** with our team.

**Expected effort**: Around 8 hours — roughly 6 building and 2 writing. If you find yourself past that, stop and write down what the blockers or pain-points were, and what you would have done next — that's a perfectly good answer.

---

## 1. Scenario

The request has come from our Platform Product Owner:

> "I want our hello-world nginx page running on Kubernetes — on AKS eventually, since that's where the rest of our platform lives. The source should live in a repo, and it should be deployed by a pipeline — not by someone running kubectl on their laptop. I want vulnerability scanning running on a schedule inside the cluster. And I don't want the page reachable by just anyone who has the URL: people should have to authenticate to get to it."

That's the whole ask, and it's deliberately modest. Where we'll push is on the parts a working demo doesn't reveal by itself — which is most of section 3.

You won't need an Azure subscription for any of this. A local cluster is the expected answer; section 4 covers where the AKS part goes instead.

---

## 2. Outcomes We're Looking For

1. **The page is served from an image you built.** nginx, a static hello world, running on Kubernetes.
2. **Everything lives in a Git repository** — Dockerfile, Kubernetes manifests, and the pipeline definition.
3. **It reaches the cluster through automation, not your laptop.** A pipeline builds the image; how it gets deployed from there is your call. The pipeline can push it, or something inside the cluster can pull it — both are fine, and section 4 goes into the trade-off. Manual `kubectl apply` is fine while you're iterating, but it shouldn't be the deployment path you demo.
4. **Vulnerability scanning runs on a schedule inside the cluster**, and the results end up somewhere a human would actually notice.
5. **Nobody reaches the page without authenticating.** An anonymous visitor holding the URL should not see the hello world page.

---

## 3. Security Expectations

This is the part we'll spend the most time on. Some of these you'll build; some you only need to be able to answer. Cover what you can in your README so we can read ahead.

- **Pipeline credentials.** How does your pipeline authenticate to the image registry, and to the cluster if it talks to it at all? Be ready to explain what you chose, what the alternatives were, and why. If a long-lived secret is stored anywhere, tell us where it lives, who can read it, and how you'd rotate it. If your deployment model means the pipeline never holds cluster credentials, say so — that's an answer, and a good one.
- **Acting on scan results.** A scheduled scan that writes to stdout meets the letter of the request and is worth very little. Who — or what — learns that a critical vulnerability has appeared, and through what path? Does anything block, alert, or roll back?
- **The finding you can't fix.** Sooner or later your nginx base image will carry a critical CVE with no patch available. What's your process? Describe it in prose; don't build it.
- **Image hygiene.** What base image did you choose, is it pinned, and does the container run as root? Justify each.
- **Scan coverage.** Scanning running workloads is one layer. What about scanning at build time, or scanning infrastructure code before it's applied? Tell us which layers you covered, which you skipped, and what each one catches that the others miss. Infrastructure scanning is a discussion point rather than something to build here — see section 4.
- **Least privilege.** What can your workload do that it doesn't need to be able to do — in the cluster, and in Azure?

We're ok if not all of it is implemented. We *are* expecting you to have thought about all of it — these answers carry more weight than anything else you submit.

That said, six areas might be more than anyone covers properly in the time. Real depth on a few beats a thin paragraph on each. Pick the ones you have the most to say about, tell us which you picked, and we'll take the rest as conversation at the showcase.

---

## 4. Guidance and Suggestions

- **Cloud platform** — the PO asked for AKS, and Azure is our production platform, so that's where this would really run. We are **not** asking you to write the Terraform. Provisioning is a showcase conversation instead: be ready to walk us through what you'd provision, what the module would own, and where the security-relevant decisions sit — cluster RBAC, registry access, network exposure, workload identity. We'd rather spend twenty minutes on your reasoning than read two hundred lines of HCL that nobody has (or maybe ever will) run.
- **Where you demo it** — a local cluster (kind, k3s, minikube) is the expected answer, and you do **not** need to pay for a live AKS cluster. If you'd rather stand one up for real, that's fine too — watch the node pool and tear it down afterwards.
- **CI system** — whatever you can actually run and demo: GitHub Actions, GitLab CI, Azure DevOps, anything else. We're interested in how the pipeline is put together, not which badge is on it.
- **Connecting the pipeline to a local cluster** — worth flagging before you lose time to it: a hosted CI runner has no network route to a cluster running on your laptop. Any of these resolutions is fine, and we'd like you to tell us which you picked and why:
    - Run a self-hosted runner locally, so the pipeline executes somewhere that can reach the cluster.
    - Split it: hosted CI builds, scans, and pushes the image to a registry, and something inside the cluster pulls and deploys it (Argo CD, Flux, or your own polling job). The cluster reaches outward, so nothing needs inbound access to it.
    - Stand up a real AKS cluster and let the pipeline deploy to it directly.

    This constraint isn't artificial, incidentally — plenty of production clusters are private for exactly this reason, and how teams work around it says a lot about their deployment model.
- **Authentication** — whatever you can demonstrate, and cheap is fine. A basic-auth annotation on an ingress, or oauth2-proxy in front of nginx against a GitHub OAuth app, are both perfectly acceptable demos. Don't lose half a day wiring up Entra ID. What we're reading is the README: what you'd actually run in production, what that protects against which your demo doesn't, and why.
- **Certificates and DNS** — not the point of the exercise. Self-signed certs, `nip.io`, or a hosts-file entry are all fine.

**On AI assistance**

Use it. We do, and we're not interested in a submission handicapped by an unrealistic do-it-yourself requirement.

What we expect is that you own everything you submit. We'll pick parts of your configuration and ask why they're there, what the alternatives were, and what you'd change. An assistant will happily generate a pipeline that authenticates with a long-lived secret pasted into a CI variable — noticing that, and fixing it, is exactly the skill this role is about.

---

## 5. Out of Scope (don't spend time on these)

- Any real application code — a static page is the whole app
- High availability, multi-region, or autoscaling
- Logging/monitoring stack
- Fixing security vulnerabilities
- Provisioning the cloud infrastructure — no Terraform, Bicep, or equivalent needed; we'll talk through it at the showcase instead

---

## 6. Deliverables

1. **A Git repository** (GitHub, GitLab, or similar) containing the Dockerfile, Kubernetes manifests, and pipeline definition. Please don't send a zip.
2. **A README** covering:
    - How to run it
    - What you built versus what you only designed
    - The decisions you made, and what you weighed them against
    - Your answers to the security expectations in section 3
    - What you'd do differently for production

    Budget real time for this — the section 3 answers are what we care about most.
3. **Evidence it works** — even a short recording or a few screenshots is fine, especially if you demoed locally.
4. *(Optional, bonus)* Anything from: an SBOM, image signing, admission policy (Kyverno/Gatekeeper), network policies, or a pipeline that fails on a severity threshold.

Please share the repository **at least a day before the showcase** so we can read it properly beforehand — it means we spend the hour on your reasoning rather than on catching up. It doesn't need to be frozen, and small fixes afterwards are fine; just avoid major changes after you send it, or we'll have read a different submission from the one you demo.

---

## 7. Showcase Format

Approximately **60 minutes**:

| Segment | Time |
|---|--------|
| Walkthrough of what you built and why | 15 min |
| Live demo — please run it, not just slides. GitHub, GitLab, local, whatever | 15 min |
| Technical Q&A | 20 min |
| Your questions for us | 10 min |

**How you present is your call** — Use whatever carries your design and reasoning best - a diagram, diagrams, an interactive webapp.. pretty much anything, just.. not a PowerPoint slide deck, please.

---

## 8. Questions

Some ambiguity in this brief is deliberate — how you resolve it is part of what we're looking at, but don't hesitate to reach out for any reason at all.

Good luck — we're rooting for you!
