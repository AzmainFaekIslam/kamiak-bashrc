# kamiak-bashrc

Bash helpers for **Kamiak**, the WSU HPC cluster (SLURM). These are shortcuts
for checking how busy the cluster is, which GPUs are free, what you're allowed
to use, how your jobs went, and where your disk space went. The output is
readable, with colour bars split by user.

It's a single file that you source. It adds functions and doesn't print
anything at startup, so `scp`, `rsync` and batch jobs keep working.

## Install

On a Kamiak login node:

```bash
git clone https://github.com/AzmainFaekIslam/kamiak-bashrc.git ~/kamiak-bashrc
echo '[ -f ~/kamiak-bashrc/kamiak.bashrc ] && . ~/kamiak-bashrc/kamiak.bashrc' >> ~/.bashrc
source ~/.bashrc
```

Update later with `git -C ~/kamiak-bashrc pull`.
To uninstall, delete that line from `~/.bashrc`.

## Partitions

The Kamiak login banner ends with the partitions you can submit to, e.g.

```
You have access to the following compute partitions:
beckman,camas,cas,dtn,kamiak,popov,vcea
```

The list depends on your accounts, but the partitions come in a few kinds:

| Kind | Examples | What it means |
|---|---|---|
| Backfill | `kamiak` | Open to everyone, covers nearly every node. Jobs here are **preemptable**: an owner's job can kill and requeue yours. Fine for short or checkpointed runs. |
| Owner (lab / college) | `beckman`, `popov`, `cas`, `vcea` | Nodes bought by a lab or college. Members get priority and aren't preempted by backfill jobs. |
| Shared priority | `camas` | Open, higher-priority, not preemptable. Holds the H100 GPU nodes (`sn16`–`sn18`). |
| Data transfer | `dtn` | For large `rsync` / `scp` copies, not compute. |

`mycluster` shows the details for your own accounts: which account opens
each partition, its limits and longest job, how busy it is, and a PREEMPT
column (`safe` / `low` / `EVICTABLE`). `nodesfree` shows how busy each one
is right now, and `gpuson` lists the GPU nodes with their partitions.

You can list several partitions and SLURM starts the job on whichever
frees up first:

```bash
#SBATCH -p popov,kamiak
```

Partitions have their own rules. For example, `popov` rejects
`--exclusive` (`sbatch: error: Exclusive flag disallowed`). To get a whole
node there, ask for all its cores with `--ntasks-per-node` and give an
explicit `--mem`. To see a partition's rules:

```bash
scontrol show partition <name>
```

For a picture of how it all fits together (head nodes, the InfiniBand
fabric, WekaFS storage, every compute node by partition, preemption and a
job's path), see
[`docs/architecture/kamiak_architecture.pdf`](docs/architecture/kamiak_architecture.pdf).
Rebuild it with `docs/architecture/compile.sh` (needs `pdflatex` with TikZ
and pgfplots).

## Optional: your partition and nodes

Set these in `~/.bashrc` **before** the line that sources `kamiak.bashrc`:

```bash
export KAMIAK_MY_PART=mylab            # partition you usually use (default: kamiak)
export KAMIAK_MY_NODES="cn[101-104]"   # nodes that are "yours" in it (default: all)
```

`KAMIAK_MY_NODES` is for lab partitions that are split informally between
people. SLURM doesn't enforce that kind of split, so a plain
`sbatch -p mylab` can land on a labmate's node. `sbmine` and `ijob` add an
`--exclude` that lists every other node in the partition, and `mynodes` shows
just your nodes.

## Commands

Run any of them with no arguments to try it out. Every function has a
comment block in `kamiak.bashrc` that explains it.

**Whole cluster**

| Command | What it shows |
|---|---|
| `nodesfree [-r]` | Every partition: cores in use / idle / total, bar split by user (`-r` = raw `sinfo -s`) |
| `whoson` | Everyone running jobs now: jobs, nodes, CPUs, share of the cluster |
| `nodeson -p <part>` | Every node in a partition, empty nodes first, bar split by user |
| `gpuson [-p <part>] [-n]` | Every GPU node: model, free GPUs, idle CPUs, free memory, who holds them (`-n` hides names) |

**You**

| Command | What it shows |
|---|---|
| `myjobs` | Your queued and running jobs (running = green) |
| `mycluster [-a]` | Your accounts and limits, QOS, partitions you may use (and whether you can be preempted there), GPUs open to you, current and past usage, fairshare, disk |
| `mynodes` | Your `KAMIAK_MY_NODES`, one line each, bar split by user |
| `hwnodes [part]` | CPUs, memory and GPUs per node |
| `nodeinfo [-n] <node>...` | One node, readable: CPU model, cores, memory, GPUs, load, jobs. Ranges work: `nodeinfo sn[16-18]` |

**Submitting**

| Command | What it does |
|---|---|
| `sbmine [sbatch opts] job.sh` | `sbatch` onto `KAMIAK_MY_PART`, restricted to `KAMIAK_MY_NODES` if set |
| `ijob [cores] [time]` | Interactive shell on a compute node (default 8 cores, 1 h) |

`sbmine` won't accept `-p`/`--partition` or `-x`/`--exclude` because they
would override its own options. Use plain `sbatch` for those. It also refuses
to submit if it can't list the partition's nodes.

**After a job**

| Command | What it shows |
|---|---|
| `jobinfo <jobid>` | State, run time, CPU time, peak memory, exit code, plus `seff` |
| `myhist [days]` | Your jobs from the last N days (default 3) |
| `mystart` | When SLURM expects your pending jobs to start |
| `tailjob <jobid>` | Follows a running job's output file (finds it for you) |

**Files**

| Command | What it does |
|---|---|
| `mkws <name>` | New scratch workspace (`mkworkspace`) and `cd` into it |
| `cdws` | `cd` into your newest scratch workspace |
| `mydisk [-u]` | Free space, quota, workspaces (`-u` also measures `$HOME`, which is slow) |
| `ktree [dir] [depth] [s]` | Directory tree with file counts (`s` adds sizes). Kamiak has no `tree` |

Scratch workspaces are deleted after 14 days. Copy anything you want to keep
back to `$HOME` or `/weka/data`.

**Documentation**

| Command | What it does |
|---|---|
| `kman` | Lists the topics from the Kamiak docs at hpc.wsu.edu |
| `kman <topic>` | Shows that page in the terminal like a man page, e.g. `kman jobs`, `kman queues`, `kman aup` |
| `kman -s <words>` | Searches the site; if only one page matches, it opens it |
| `kman -u <topic>` | Prints the page's web address |
| `kman -r <topic>` | Fetches the page again instead of using the cache |

Pages come from the site's WordPress API and are cached for a day in
`~/.cache/kman`, so `kman` still works from that cache when the site is
down. It needs `curl` and `python3`, and uses the system `/usr/bin/python3`
so loaded modules and conda environments don't affect it.

## Colours

In the bars, **you are bold white**. Everyone else gets red, green, blue,
yellow, magenta, cyan (then darker shades), ranked by how much they're using.
Dark grey `(other)` means cores SLURM counts as allocated that no single-node
job explains, usually multi-node jobs.

Colours appear only on a terminal. For letters instead (W = you, R G B ...),
use:

```bash
NO_COLOR=1 nodeson -p kamiak
```

Piping output (`myjobs | grep ...`) gives plain text.

## Other things it sets

- **History:** 50k lines in memory and 100k in the file, timestamps,
  duplicates skipped, appended rather than overwritten, so several terminals
  don't erase each other. To change any of this, override it in `~/.bashrc`
  after the source line.
- `/etc/bashrc` is sourced only if your `~/.bashrc` hasn't already done it.

## Notes

- Everything except `kman` reads SLURM (`sinfo`, `squeue`, `scontrol`,
  `sacct`, `sacctmgr`, `sreport`, `sshare`), so it only works on Kamiak.
  `kman` only needs internet access.
- These commands only read cluster state. Nothing here changes anything except
  `sbmine`, `ijob` and `mkws`, plus `kman`'s cache in `~/.cache/kman`.
- If you add something that prints at startup, wrap it in
  `[[ $- == *i* ]] && ...`.

## License

MIT
