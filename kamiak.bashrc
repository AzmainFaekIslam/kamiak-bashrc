# kamiak.bashrc  --  shell helpers for the Kamiak cluster (WSU HPC, SLURM)
#
# Source it from your own ~/.bashrc:
#     [ -f ~/kamiak-bashrc/kamiak.bashrc ] && . ~/kamiak-bashrc/kamiak.bashrc
# See README.md for install notes and examples.
#
# =============================================================================
# QUICK REFERENCE  --  every command defined in this file
# =============================================================================
#
#   Whole cluster
#     nodesfree [-r]         How busy each partition is, bar split by user (-r = plain sinfo -s)
#     whoson                 Who is running jobs right now, biggest first, bar in user colour
#     nodeson -p <part>      Every node in one partition: bar split by user (me = white)
#     gpuson [-p <part>] [-n]  Every GPU node: free GPUs, model, bar of GPUs by user (-n = hide names)
#
#   Me and my nodes
#     myjobs                 My queued and running jobs (running = green)
#     mycluster [-a]         My accounts, partition access, CPU/GPU/RAM/disk limits, usage, uptime
#     mynodes                The nodes in $KAMIAK_MY_NODES; bar coloured by user (me = white)
#     hwnodes [part]         Hardware per node: CPUs, memory, GPUs (default: $KAMIAK_MY_PART)
#     nodeinfo [-n] <node>   One node, readable: CPU, cores, memory, GPUs, jobs (sn[16-18] ok)
#
#   Submitting and running
#     sbmine <script>        sbatch to $KAMIAK_MY_PART, ONLY onto $KAMIAK_MY_NODES (if set)
#     ijob [cores] [time]    Interactive shell on $KAMIAK_MY_PART (same node restriction)
#
#   After a job
#     jobinfo <jobid>        How a job went: state, run time, peak memory, exit code
#     myhist [days]          My jobs from the last few days (default 3)
#     mystart                When SLURM expects my pending jobs to start
#     tailjob <jobid>        Watch a running job's output file live
#
#   Files and storage
#     mkws <name>            Make a new scratch workspace and cd into it
#     cdws                   cd into my newest scratch workspace
#     mydisk [-u]            Disk space, quota and workspaces (-u = also size of $HOME)
#     ktree [dir] [depth] [s]  Directory tree with file counts (and sizes with s)
#
# Nothing in this file prints anything when the shell starts. Keep it that way:
# output at startup breaks scp, rsync and some batch jobs. If you add something
# that prints, wrap it like this:   [[ $- == *i* ]] && echo "hello"
# =============================================================================


# =============================================================================
# 0. System defaults
# =============================================================================
# Load Kamiak's site-wide settings (module command, default PATH, ...) unless
# your own ~/.bashrc already did (RHEL's /etc/bashrc sets BASHRCSOURCED).
if [ -z "${BASHRCSOURCED:-}" ] && [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi


# =============================================================================
# 1. Your partition and nodes  (optional, set these in ~/.bashrc BEFORE sourcing)
# =============================================================================
#
# KAMIAK_MY_PART   the partition you usually run on (e.g. your lab's partition).
#                  Default for hwnodes, sbmine and ijob. Default: kamiak.
#
# KAMIAK_MY_NODES  a SLURM hostlist of the nodes that are "yours" inside that
#                  partition, e.g. "cn[161-167],cn178". Useful when a lab
#                  partition is split informally between people: SLURM does NOT
#                  enforce such a split, so a plain `sbatch -p <part>` can land
#                  on someone else's node. sbmine / ijob exclude every other node
#                  in the partition, and mynodes shows just these.
#                  Leave empty to use the whole partition.
#
#   export KAMIAK_MY_PART=mylab
#   export KAMIAK_MY_NODES="cn[101-104]"
export KAMIAK_MY_PART="${KAMIAK_MY_PART:-kamiak}"
export KAMIAK_MY_NODES="${KAMIAK_MY_NODES:-}"


# =============================================================================
# 2. Helpers for drawing usage bars
# =============================================================================
# These are used by the views below. You don't call them directly.

# _bar USED TOTAL [WIDTH]
#   Draws a text bar showing USED out of TOTAL, WIDTH characters wide (default 20).
#   Example:  _bar 5 10 10   ->   [█████░░░░░]
#   If the numbers are missing or TOTAL is 0, prints blank space of the same
#   width so table columns still line up.
_bar() {
    local u=$1 t=$2 w=${3:-20} f i s=""
    if ! [[ $u =~ ^[0-9]+$ && $t =~ ^[0-9]+$ ]] || [ "$t" -le 0 ]; then
        printf '%*s' $((w + 2)) ''
        return
    fi
    f=$(( (u * w + t / 2) / t ))    # number of filled blocks, rounded
    for ((i = 1; i <= w; i++)); do
        if [ "$i" -le "$f" ]; then s+="█"; else s+="░"; fi
    done
    printf '[%s]' "$s"
}

# The same bar, written for awk. The views below glue this text onto the front
# of their awk program ( awk "$_AWK_BAR"'...' ), so awk code can call
# bar(used, total, width). One copy here means one place to fix.
_AWK_BAR='
    function bar(u, t, w,   f, i, s) {
        if (t <= 0) return ""
        f = int(u * w / t + 0.5); s = "["
        for (i = 1; i <= w; i++) s = s (i <= f ? "█" : "░")
        return s "]"
    }'

# The per-user version of the bar, also written for awk. Glue it on the front of
# an awk program together with _AWK_BAR, then:
#   BEGIN { ub_init(me, plain) }             me = $USER, plain = $NO_COLOR
#   for each (unit, user, cpus):  ub_add(unit, user, cpus)    unit = a node or a partition
#   END   { ub_assign()                      # fix colours: biggest users first
#           bar = ub_draw(unit, T, A, 20)    # T total cores, A allocated; legend in ub_leg
#           ub_key(12) }                     # colour key line
# Colours: me = bold white; others take red, green, blue, yellow, magenta, cyan
# (then bright versions) in order of total CPUs in that view, biggest first;
# past 12 users the rest share plain grey. Cores that SLURM counts as allocated
# but no running job in the list explains show as dark-grey "(other)".
# NO_COLOR set -> letters (W = me, R G B Y M C r g b y m c, - = grey, ? = other).
# No single quotes inside: this whole block lives in a bash single-quoted string.
_AWK_UBAR='
    function ub_init(m, p) {
        ub_me = m; ub_plain = p
        ub_np = split("91 92 94 93 95 96 31 32 34 33 35 36", ub_pal, " ")
        split("R G B Y M C r g b y m c", ub_ltr, " ")
    }
    function ub_add(unit, user, cpus) {
        ub_use[unit, user] += cpus; ub_got[unit] += cpus; ub_tot[user] += cpus
        if (!((unit SUBSEP user) in ub_has)) { ub_has[unit SUBSEP user] = 1; ub_ul[unit] = ub_ul[unit] " " user }
    }
    function ub_assign(   u, i, j, t, m) {
        for (u in ub_tot) if (u != ub_me) ub_nm[++m] = u
        for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++)
            if (ub_tot[ub_nm[j]] > ub_tot[ub_nm[i]] || (ub_tot[ub_nm[j]] == ub_tot[ub_nm[i]] && ub_nm[j] < ub_nm[i])) { t = ub_nm[i]; ub_nm[i] = ub_nm[j]; ub_nm[j] = t }
        for (i = 1; i <= m; i++) ub_ci[ub_nm[i]] = i
        ub_n = m
    }
    function ub_c(u) {
        if (u == ub_me) return "1;97"
        if (u == "(other)") return "90"
        return (ub_ci[u] <= ub_np) ? ub_pal[ub_ci[u]] : "37"
    }
    function ub_l(u) {
        if (u == ub_me) return "W"
        if (u == "(other)") return "?"
        return (ub_ci[u] <= ub_np) ? ub_ltr[ub_ci[u]] : "-"
    }
    function ub_blk(u) { return (ub_plain != "") ? ub_l(u) : sprintf("\033[%sm█\033[0m", ub_c(u)) }
    function ub_idle() { return (ub_plain != "") ? "." : "\033[90m░\033[0m" }
    # one solid bar in one user colour (used where each row is one user)
    function ub_solid(u, used, total, w,   f, i, s) {
        f = (total > 0) ? int(used * w / total + 0.5) : 0; s = "["
        for (i = 1; i <= w; i++) s = s ((i <= f) ? ub_blk(u) : ub_idle())
        return s "]"
    }
    # the split bar for one unit; sets ub_leg to the legend text
    function ub_draw(unit, T, A, W,   ul2, nu, i, j, t, target, s, mx, bar, lg) {
        ul2 = ub_ul[unit]
        if (A > ub_got[unit]) { ub_use[unit, "(other)"] = A - ub_got[unit]; ul2 = ul2 " (other)" }
        nu = split(ul2, ub_us, " ")
        for (i = 1; i <= nu; i++) for (j = i + 1; j <= nu; j++)
            if (ub_use[unit, ub_us[j]] > ub_use[unit, ub_us[i]]) { t = ub_us[i]; ub_us[i] = ub_us[j]; ub_us[j] = t }
        target = int(A * W / T + 0.5); if (A > 0 && target == 0) target = 1
        s = 0
        for (i = 1; i <= nu; i++) { ub_b[i] = int(ub_use[unit, ub_us[i]] * W / T); if (ub_b[i] == 0) ub_b[i] = 1; s += ub_b[i] }
        while (s > target) { mx = 1; for (i = 2; i <= nu; i++) if (ub_b[i] > ub_b[mx]) mx = i; if (ub_b[mx] <= 1) break; ub_b[mx]--; s-- }
        while (s < target) { mx = 1; for (i = 2; i <= nu; i++) if (ub_use[unit, ub_us[i]] / (ub_b[i] + 0.5) > ub_use[unit, ub_us[mx]] / (ub_b[mx] + 0.5)) mx = i; ub_b[mx]++; s++ }
        bar = "["
        for (i = 1; i <= nu; i++) for (j = 0; j < ub_b[i]; j++) bar = bar ub_blk(ub_us[i])
        for (j = s; j < W; j++) bar = bar ub_idle()
        lg = ""
        for (i = 1; i <= nu; i++)
            lg = lg (i > 1 ? "  " : "") ((ub_plain != "") ? ub_l(ub_us[i]) "=" : sprintf("\033[%sm●\033[0m ", ub_c(ub_us[i]))) ub_us[i] "(" ub_use[unit, ub_us[i]] ")"
        ub_leg = (nu == 0) ? "-" : lg
        return bar "]"
    }
    function ub_key(maxn,   i, k) {
        printf "key: "
        printf ((ub_plain != "") ? "W=" : "\033[1;97m█\033[0m ") "%s (me)", ub_me
        for (i = 1; i <= ub_n && i <= maxn; i++) printf "   " ((ub_plain != "") ? ub_l(ub_nm[i]) "=" : sprintf("\033[%sm█\033[0m ", ub_c(ub_nm[i]))) "%s", ub_nm[i]
        if (ub_n > maxn) printf "   (+%d more users)", ub_n - maxn
        printf "   " ((ub_plain != "") ? ".=" : "\033[90m░\033[0m ") "idle\n"
    }'

# _jobcol STATE_FIELD [HEADER_LINES]
#   A filter for job listings: a row whose state field is R / RUNNING is printed
#   green, every other row (PD, CG, COMPLETED, FAILED, ...) white. The first
#   HEADER_LINES lines (default 1) are passed through untouched, which also
#   covers sacct's dashed second line (use 2 there).
#   STATE_FIELD is the column number of the state, counting words. Colours only
#   when output goes to a terminal and NO_COLOR is not set, so pipes, scripts
#   and `myjobs | grep ...` still get plain text.
#   Example:  squeue -u $USER -o "%.20i %.20j %.2t" | _jobcol 3
_jobcol() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        awk -v f="$1" -v h="${2:-1}" '
            NR <= h { print; next }
            $f == "R" || $f == "RUNNING" { printf "\033[92m%s\033[0m\n", $0; next }
            { printf "\033[97m%s\033[0m\n", $0 }'
    else
        cat
    fi
}

# _hdr TEXT
#   A section heading for the longer views (mycluster): bold cyan on a terminal,
#   plain text otherwise.
_hdr() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[1;36m== %s ==\033[0m\n' "$1"
    else printf '== %s ==\n' "$1"; fi
}

# Awk helpers for SLURM TRES strings such as "cpu=64,mem=500G,gres/gpu=4".
# Glued on the front of an awk program (together with _AWK_BAR if needed):
#   tv(s, re)           value of the first item whose "name=" matches re ("" if none)
#   gbv(v)              memory string (500G, 512000M, 2T, bare number = MB) in GB
#   tight(a, b, c, k)   the smallest limit for k = "cpu" | "mem" | "gpu" found in
#                       the TRES strings a, b, c; "-" when none sets one
#   ngpu(s)             GPU count in a gres string ("gpu:tesla:4(S:0-1)", "gpu:2")
#   secs(t) / dur(s)    SLURM time (d-hh:mm:ss) to seconds / seconds to "2d 03h 05m"
# No single quotes inside: this whole block lives in a bash single-quoted string.
_AWK_TRES='
    function tv(s, re,   n, i, it) {
        n = split(s, it, ",")
        for (i = 1; i <= n; i++) if (it[i] ~ re) { sub(/^[^=]*=/, "", it[i]); return it[i] }
        return ""
    }
    function gbv(v,   n, u) {
        if (v == "") return ""
        n = v + 0; u = v; sub(/^[0-9.]+/, "", u); u = toupper(u)
        if (u == "K") return n / 1048576
        if (u == "G") return n
        if (u == "T") return n * 1024
        return n / 1024
    }
    function lim1(s, k) {
        if (k == "mem") return gbv(tv(s, "^mem="))
        if (k == "cpu") return tv(s, "^cpu=")
        return tv(s, "^gres/gpu(:[^=]*)?=")
    }
    function tight(a, b, c, k,   best, v, i, s) {
        best = ""
        for (i = 1; i <= 3; i++) {
            s = (i == 1) ? a : (i == 2) ? b : c
            v = lim1(s, k)
            if (v != "" && (best == "" || v + 0 < best + 0)) best = v
        }
        if (best == "") return "-"
        return (k == "mem") ? sprintf("%gG", best) : best
    }
    function ngpu(s,   k, i, it, f, c, t) {
        t = 0; k = split(s, it, ",")
        for (i = 1; i <= k; i++) {
            if (it[i] !~ /gpu/) continue
            sub(/\(.*/, "", it[i]); c = split(it[i], f, ":")
            t += (f[c] ~ /^[0-9]+$/) ? f[c] : 1
        }
        return t
    }
    function secs(t,   d, a, n) {
        if (t !~ /^[0-9]/) return -1
        d = 0
        if (t ~ /-/) { split(t, a, "-"); d = a[1]; t = a[2] }
        n = split(t, a, ":")
        return d * 86400 + ((n == 3) ? a[1] * 3600 + a[2] * 60 + a[3] : (n == 2) ? a[1] * 60 + a[2] : a[1])
    }
    function dur(s,   d, h, m) {
        if (s < 0) return "-"
        d = int(s / 86400); h = int(s % 86400 / 3600); m = int(s % 3600 / 60)
        return d ? sprintf("%dd %02dh %02dm", d, h, m) : sprintf("%dh %02dm", h, m)
    }'

# Note on SLURM's CPU numbers: sinfo's "%C" prints four numbers as A/I/O/T:
#   A = allocated (in use), I = idle, O = other (down/drained), T = total.
# The awk code below splits on "/" to get them.


# =============================================================================
# 3. Whole-cluster views
# =============================================================================

# nodesfree  --  how busy is each partition?
#
#   nodesfree        one line per partition: cores in use, idle, total, and a bar
#                    split by user (me = white, others coloured, see _AWK_UBAR)
#   nodesfree -r     the raw `sinfo -s` output instead
#
# (nodesfree used to be an alias. The unalias line lets you re-source this file
#  in an old shell without a syntax error.)
unalias nodesfree 2>/dev/null
nodesfree() {
    if [ "$1" = "-r" ]; then sinfo -s; return; fi
    { sinfo -h -o "%R %C" | sort -u; echo "---"; squeue -h -t R -o "%P %u %C"; } | awk -v me="$USER" -v plain="${NO_COLOR:-}" "$_AWK_UBAR"'
        BEGIN { ub_init(me, plain); part = 1 }
        $0 == "---" { part = 2; next }
        part == 1 && NF >= 2 {
            split($2, a, "/")                     # A/I/O/T, see section 2
            p[++n] = $1; al[n] = a[1]; id[n] = a[2]; to[n] = a[4]; known[$1] = 1
            if (length($1) > w) w = length($1)    # widest partition name
        }
        part == 2 && NF >= 3 && ($1 in known) { ub_add($1, $2, $3) }   # multi-partition names fall to (other)
        END {
            ub_assign()
            if (w < 9) w = 9
            printf "%-*s %7s %7s %7s  %-22s %s\n", w, "PARTITION", "ALLOC", "IDLE", "TOTAL", "UTILISATION BY USER", "USED"
            for (i = 1; i <= n; i++) {
                b = (to[i] > 0) ? ub_draw(p[i], to[i], al[i], 20) : ""
                printf "%-*s %7d %7d %7d  %s %3d%%\n", w, p[i], al[i], id[i], to[i], b, (to[i] ? 100 * al[i] / to[i] : 0)
            }
            ub_key(12)
        }'
}

# whoson  --  who is using the cluster right now?
#
#   One line per user with running jobs: number of jobs, nodes and CPUs, plus
#   that user's share of ALL running CPUs on Kamiak. Biggest CPU user first.
#   Each user's bar has their colour (me = white), in rank order: red, green, ...
whoson() {
    squeue -h -t R -o "%u %D %C" | awk -v me="$USER" -v plain="${NO_COLOR:-}" "$_AWK_UBAR"'
        BEGIN { ub_init(me, plain) }
        {n[$1]+=$2; c[$1]+=$3; j[$1]++; tot+=$3; ub_add("all", $1, $3); if (length($1) > w) w = length($1)}
        END {
            ub_assign()
            printf "%-*s %6s %8s %7s  %s\n", w, "USER", "JOBS", "NODES", "CPUS", "SHARE OF RUNNING CPUS"
            for (u in n) printf "%-*s %6d %8d %7d  %s %3d%%\n", w, u, j[u], n[u], c[u], ub_solid(u, c[u], tot, 20), (tot ? 100 * c[u] / tot : 0)
        }' | (read -r h; echo "$h"; sort -k4 -nr)    # keep header on top, sort by CPUS
}

# nodeson -p <partition>  --  node-by-node view of one partition
#
#   Example:  nodeson -p kamiak
#   Shows every node's cores (total / in use / idle), a bar split by user
#   (me = white, others coloured) and each user's CPUs. Completely empty nodes
#   are listed first, so free nodes are easy to spot.
#   Users are looked up by NODE, not by partition, so jobs that came in from
#   another partition are counted too; cores nobody can be matched to show as
#   dark-grey "(other)".
nodeson() {
    local part="" nodes
    while getopts "p:" opt; do
        case "$opt" in
            p) part="$OPTARG" ;;
            *) echo "Usage: nodeson -p <partition>"; return 1 ;;
        esac
    done
    if [ -z "$part" ]; then
        echo "Usage: nodeson -p <partition>"
        return 1
    fi
    nodes=$(sinfo -h -N -p "$part" -o "%N" | sort -u | paste -sd, -)
    { sinfo -h -N -p "$part" -o "%N %C"; echo "---"; squeue -h -t R -w "$nodes" -o "%N %u %C"; } | awk -v part="$part" -v me="$USER" -v plain="${NO_COLOR:-}" "$_AWK_UBAR"'
        BEGIN { ub_init(me, plain); sec = 1 }
        $0 == "---" { sec = 2; next }
        sec == 1 && NF >= 2 {                     # sinfo: node A/I/O/T
            split($2, a, "/")
            total[$1]=a[4]; alloc[$1]=a[1]; idle[$1]=a[2]
            order[++n]=$1
        }
        sec == 2 && NF >= 3 && ($1 in total) { ub_add($1, $2, $3) }
        END {
            ub_assign()
            printf "%-12s %-8s %6s %6s %6s  %-22s %4s  %s\n", "PARTITION", "NODE", "TOTAL", "ALLOC", "IDLE", "USAGE", "", "USER(S) (cpus)"
            for (pass = 0; pass <= 1; pass++)     # pass 0: empty nodes, pass 1: busy nodes
                for (i=1;i<=n;i++) {
                    nd=order[i]
                    if ((alloc[nd]==0) != (pass==0)) continue
                    if (total[nd] <= 0) continue
                    b = ub_draw(nd, total[nd], alloc[nd], 20)
                    printf "%-12s %-8s %6d %6d %6d  %s %3d%%  %s\n", part, nd, total[nd], alloc[nd], idle[nd], b, (total[nd]?100*alloc[nd]/total[nd]:0), ub_leg
                }
            ub_key(12)
        }'
}

# gpuson [-p <partition>] [-n]  --  GPU availability, one line per GPU node
#
#   Example:  gpuson              every GPU node on Kamiak
#             gpuson -p camas     only the camas GPU nodes
#             gpuson -n           no usernames: my GPUs stay white, everyone
#                                 else is lumped together as "others"
#   Like nodeson, but the bar counts GPUs, not cores: one segment per user's
#   GPUs (me = white, others coloured), free GPUs as dim dots. Also shows the
#   card model, the node's idle CPUs and free memory (a GPU job needs those too)
#   and every partition the node is in. Nodes with a free GPU come first, then
#   full ones, then DOWN / DRAIN / MAINT nodes, whose free GPUs show as "-".
#   GPU nodes are found from SLURM (Gres=gpu...), so new cards appear by
#   themselves. As of mid-2026 (check with gpuson, this list goes stale):
#
#     sn14       2x A100 40 GB       vcea   (group only)
#     sn15       4x A100 40 GB       cas    (group only)
#     sn16-sn18  4x H100 80 GB each  camas  (open, priority, not preemptable)
#     sn19       2x H100-NVL 94 GB   yan    (group only)
#
#   All of them are also in the kamiak backfill partition (preemptable).
#   Request GPUs with  --gres=gpu:tesla:N.
#   A user's GPUs come from their jobs' gres request; GPUs SLURM counts as
#   allocated that no single-node job explains show as dark-grey "(other)".
gpuson() {
    local part="" anon="" opt OPTIND=1 info nodes
    while getopts "p:n" opt; do
        case "$opt" in
            p) part="$OPTARG" ;;
            n) anon=1 ;;
            *) echo "Usage: gpuson [-p <partition>] [-n]"; return 1 ;;
        esac
    done
    info=$(scontrol -o show node 2>/dev/null | grep -E '(^| )Gres=[^ ]*gpu')
    if [ -n "$part" ]; then
        info=$(grep -E "(^| )Partitions=([^ ]*,)?${part}(,| |$)" <<< "$info")
    fi
    if [ -z "$info" ]; then
        echo "gpuson: no GPU nodes found${part:+ in partition $part}" >&2
        return 1
    fi
    nodes=$(sed -n 's/^NodeName=\([^ ]*\).*/\1/p' <<< "$info" | paste -sd, -)
    { echo "$info"; echo "---"; squeue -h -t R -w "$nodes" -o "%N %u %b"; } | awk -v me="$USER" -v anon="$anon" -v plain="${NO_COLOR:-}" "$_AWK_UBAR"'
        # GPU count in a gres string: "gpu:tesla:4(S:0-1)", "gpu:2", "gres/gpu:1", "(null)"
        function ngpu(s,   k, i, it, f, c, t) {
            t = 0; k = split(s, it, ",")
            for (i = 1; i <= k; i++) {
                if (it[i] !~ /gpu/) continue
                sub(/\(.*/, "", it[i]); c = split(it[i], f, ":")
                t += (f[c] ~ /^[0-9]+$/) ? f[c] : 1
            }
            return t
        }
        # GPU count from a TRES list: "cpu=47,mem=899020M,gres/gpu=4"
        function tgpu(s,   k, i, it, t, typed) {
            t = 0; typed = 0; k = split(s, it, ",")
            for (i = 1; i <= k; i++) {
                if (it[i] ~ /^gres\/gpu=/)  { sub(/.*=/, "", it[i]); return it[i] + 0 }
                if (it[i] ~ /^gres\/gpu:/)  { sub(/.*=/, "", it[i]); typed += it[i] }
            }
            return typed
        }
        BEGIN { ub_init(me, plain); sec = 1 }
        $0 == "---" { sec = 2; next }
        sec == 1 {                                # scontrol -o: Key=value fields
            nd = ""; g = ""; cfg = -1; ga = 0; mdl = "?"; gm = ""; st = "?"; pt = "?"; ca = 0; ct = 0; mr = 0; ma = 0
            for (i = 1; i <= NF; i++) {
                k = $i; sub(/=.*/, "", k); v = $i; sub(/^[^=]*=/, "", v)
                if (k == "NodeName") nd = v
                else if (k == "Gres") g = v
                else if (k == "CfgTRES") cfg = tgpu(v)
                else if (k == "AllocTRES") ga = tgpu(v)
                else if (k == "CPUAlloc") ca = v
                else if (k == "CPUTot") ct = v
                else if (k == "RealMemory") mr = v
                else if (k == "AllocMem") ma = v
                else if (k == "State") st = v
                else if (k == "Partitions") pt = v
                else if (k == "AvailableFeatures") {
                    nf = split(v, ft, ",")
                    for (j = 1; j <= nf; j++) {
                        if (ft[j] ~ /^[a-z][0-9]+(-[a-z]+)?$/) mdl = toupper(ft[j])           # a100, h100, h100-nvl
                        if (ft[j] ~ /^(gpu-mem|mem-per-gpu)-/) { gm = ft[j]; sub(/.*-/, "", gm) }  # 80GB
                    }
                }
            }
            if (nd == "") next
            T = (cfg > 0) ? cfg : ngpu(g); if (T <= 0) next
            order[++n] = nd; gt[nd] = T; gal[nd] = (ga > T) ? T : ga
            model[nd] = mdl (gm != "" ? " " gm : ""); state[nd] = st; parts[nd] = pt
            cpu[nd] = (ct - ca) "/" ct; mem[nd] = int((mr - ma) / 1024) "G"
            bad[nd] = (st ~ /DOWN|DRAIN|FAIL|MAINT|NOT_RESP|POWER/)
            if (length(pt) > pw) pw = length(pt)
            next
        }
        sec == 2 && NF >= 3 && ($1 in gt) { k = ngpu($3); if (k > 0) ub_add($1, (anon && $2 != me) ? "others" : $2, k) }   # multi-node jobs fall to (other)
        END {
            ub_assign()
            if (pw < 10) pw = 10
            printf "%-*s %-6s %-11s %-13s %4s %5s %4s  %-22s %4s  %8s %8s  %s\n", pw, "PARTITIONS", "NODE", "STATE", "GPU", "GPUS", "ALLOC", "FREE", "USAGE (GPUs)", "", "CPU IDLE", "MEM FREE", "USER(S) (gpus)"
            tt = 0; tf = 0
            for (pass = 0; pass <= 2; pass++)     # 0: has a free GPU, 1: full, 2: unavailable
                for (i = 1; i <= n; i++) {
                    nd = order[i]; T = gt[nd]; A = gal[nd]
                    p = bad[nd] ? 2 : (A < T ? 0 : 1)
                    if (p != pass) continue
                    b = ub_draw(nd, T, A, 20)
                    fr = bad[nd] ? "-" : T - A
                    printf "%-*s %-6s %-11s %-13s %4d %5d %4s  %s %3d%%  %8s %8s  %s\n", pw, parts[nd], nd, substr(state[nd], 1, 11), model[nd], T, A, fr, b, int(100 * A / T + 0.5), cpu[nd], mem[nd], ub_leg
                    tt += T; if (!bad[nd]) tf += T - A
                }
            printf "%d of %d GPUs free on %d GPU nodes\n", tf, tt, n
            ub_key(12)
        }'
}


# =============================================================================
# 4. Me and my nodes
# =============================================================================

# myjobs  --  my queued and running jobs
#   Columns: job ID, name, partition, state (R = running, PD = pending),
#   time used, CPUs, and the node list (or the reason a job is still waiting).
#   Running jobs (R) are green, everything else (PD, CG, ...) white; see _jobcol.
unalias myjobs 2>/dev/null
myjobs() { squeue -u "$USER" -o "%.20i %.20j %.9P %.2t %.11M %.5C %.20R" "$@" | _jobcol 4; }

# _mc_assoc USER  --  one normalised line per SLURM association (used by mycluster)
#   account|partition|qos|cpu|mem(GB)|gpu|maxjobs|maxsubmit|maxwall
#   cpu / mem / gpu are the tightest of GrpTRES, MaxTRES and MaxTRESPerUser;
#   "-" = nothing set at this level (the limit may still come from a parent
#   account or from the QOS), partition "all" = not restricted to one partition.
_mc_assoc() {
    sacctmgr -n -P show assoc user="$1" format=Account,Partition,QOS,GrpTRES,MaxTRES,MaxTRESPerUser,MaxJobs,MaxSubmit,MaxWall 2>/dev/null \
    | awk -F'|' "$_AWK_TRES"'{
        print $1 "|" ($2 == "" ? "all" : $2) "|" ($3 == "" ? "-" : $3) "|" tight($4, $5, $6, "cpu") "|" tight($4, $5, $6, "mem") "|" tight($4, $5, $6, "gpu") \
              "|" ($7 == "" ? "-" : $7) "|" ($8 == "" ? "-" : $8) "|" ($9 == "" ? "-" : $9)
    }'
}

# mycluster [-a]  --  everything about what I may use on Kamiak, in seven blocks
#   1. Header      login node uptime and load, my groups, default account
#   2. Accounts    each account with its CPU / memory / GPU / job / wall-time
#                  limits (* = default account: jobs without --account go there)
#   3. QOS         the limits of the QOS levels my accounts use
#   4. Partitions  the partitions I may submit to: nodes, cores, memory, GPUs,
#                  longest job, how busy it is now, and which of my accounts
#                  opens it. -a also lists the partitions I may NOT use.
#   5. Usage now   my running / pending jobs per account against the limits
#                  above (bar = share of the CPU limit), how long the longest
#                  job has run, when the next one ends, CPU-hours so far
#   6. Usage past  this month and this year: jobs, wall hours, CPU / GPU hours,
#                  and fairshare (1 = barely used, 0.5 = at my share, ~0 = heavy)
#   7. Disk        filesystems and quota (details and workspaces: mydisk)
#   A "-" limit means none is set on that account; a parent account or the QOS
#   may still impose one. Slurm also lets a partition allow a PARENT account, which
#   this view cannot see: if a partition says "no" but you expect yes, check
#   scontrol show partition <name>.
#   Colours only on a terminal and when NO_COLOR is not set.
mycluster() {
    local opt OPTIND=1 all="" me="$USER" grp lim def color="" month year d openf
    while getopts "a" opt; do
        case "$opt" in
            a) all=1 ;;
            *) echo "Usage: mycluster [-a]" >&2; return 1 ;;
        esac
    done
    if ! command -v sacctmgr >/dev/null 2>&1; then
        echo "mycluster: SLURM commands not found (run this on Kamiak)" >&2; return 1
    fi
    [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && color=1
    month=$(date +%Y-%m-01); year=$(date +%Y-01-01)
    grp=$(id -Gn | tr ' ' ',')
    lim=$(_mc_assoc "$me")
    if [ -z "$lim" ]; then echo "mycluster: SLURM has no account for $me" >&2; return 1; fi
    def=$(sacctmgr -n -P show user "$me" format=DefaultAccount 2>/dev/null | head -1)

    # 1. Header
    _hdr "$me on $(hostname -s)"
    printf '  %-13s up %s, load %s, this shell open %s\n' "Login node" "$(uptime -p | sed 's/^up //')" \
        "$(cut -d' ' -f1-3 /proc/loadavg)" "$(ps -o etime= -p $$ | tr -d ' ')"
    printf '  %-13s %s\n' "Groups" "${grp//,/, }"
    printf '  %-13s %s   (jobs without --account are charged here)\n' "Default acct" "${def:-?}"
    [ -n "$KAMIAK_MY_NODES" ] && printf '  %-13s %s in %s   (see mynodes)\n' "My nodes" "$KAMIAK_MY_NODES" "$KAMIAK_MY_PART"

    # 2. Accounts and limits
    echo; _hdr "Accounts and limits   (* = default account, - = none set)"
    awk -F'|' -v def="$def" 'BEGIN { printf "%-14s %-10s %-22s %6s %7s %5s %6s %7s %-12s\n", "ACCOUNT", "PARTITION", "QOS", "CPUS", "MEM", "GPUS", "JOBS", "SUBMIT", "MAX WALL" }
        { printf "%-14s %-10s %-22.22s %6s %7s %5s %6s %7s %-12s\n", $1 ($1 == def ? " *" : ""), $2, $3, $4, $5, $6, $7, $8, $9 }' <<< "$lim"

    # 3. QOS limits (only the QOS levels my accounts name; all of them if none named)
    echo; _hdr "QOS limits   (per user, on top of the account limits)"
    sacctmgr -n -P show qos format=Name,MaxTRESPU,MaxJobsPU,MaxWall,GrpTRES,Priority 2>/dev/null \
    | awk -F'|' -v mine="$(cut -d'|' -f3 <<< "$lim" | paste -sd, -)" "$_AWK_TRES"'
        BEGIN {
            n = split(mine, a, ",")
            for (i = 1; i <= n; i++) if (a[i] != "" && a[i] != "-") { want[a[i]] = 1; nw++ }
            printf "%-16s %6s %7s %5s %6s %-12s %8s   %s\n", "QOS", "CPUS", "MEM", "GPUS", "JOBS", "MAX WALL", "PRIORITY", "CLUSTER-WIDE CAP (cpu / gpu)"
        }
        (nw == 0 || ($1 in want)) {
            printf "%-16s %6s %7s %5s %6s %-12s %8s   %s / %s\n", $1, tight($2, "", "", "cpu"), tight($2, "", "", "mem"), tight($2, "", "", "gpu"),
                ($3 == "" ? "-" : $3), ($4 == "" ? "-" : $4), ($6 == "" ? "-" : $6), tight($5, "", "", "cpu"), tight($5, "", "", "gpu")
        }'

    # 4. Partitions
    openf=$(mktemp) || return
    echo; _hdr "Partitions   (what you may submit to; -a also shows the rest)"
    { sed 's/^/L|/' <<< "$lim"; echo "---"; scontrol -o show partition 2>/dev/null; echo "---"; sinfo -h -o "%R %C %D %m %G" 2>/dev/null; } \
    | awk -v groups="$grp" -v all="$all" -v color="$color" -v ofile="$openf" "$_AWK_BAR$_AWK_TRES"'
        # items of csv a that are (keep=1) / are not (keep=0) in csv b
        function inter(a, b, keep,   n, m, i, j, x, y, hit, r) {
            n = split(a, x, ","); m = split(b, y, ","); r = ""
            for (i = 1; i <= n; i++) {
                hit = 0
                for (j = 1; j <= m; j++) if (x[i] == y[j]) hit = 1
                if (x[i] != "" && hit == keep) r = r (r == "" ? "" : ",") x[i]
            }
            return r
        }
        function col(code, s) { return color ? "\033[" code "m" s "\033[0m" : s }
        function memfmt(gb) { return (gb >= 1024) ? sprintf("%.1fT", gb / 1024) : sprintf("%dG", gb) }
        BEGIN { sec = 1 }
        $0 == "---" { sec++; next }
        sec == 1 {                                       # my associations
            split($0, f, "|"); a = f[2]
            if (!(a in seen)) { seen[a] = 1; accts = accts (accts == "" ? "" : ",") a }
            if (f[3] == "all") hasall[a] = 1; else spec[a, f[3]] = 1
            nq = split(f[4], q, ",")
            for (i = 1; i <= nq; i++) if (q[i] != "-" && index("," myqos ",", "," q[i] ",") == 0) myqos = myqos (myqos == "" ? "" : ",") q[i]
            next
        }
        sec == 2 {                                       # scontrol -o show partition
            nm = ""
            for (i = 1; i <= NF; i++) {
                k = $i; sub(/=.*/, "", k); v = $i; sub(/^[^=]*=/, "", v)
                if (k == "PartitionName") { nm = v; order[++np] = nm }
                else if (nm != "") pf[nm, k] = v
            }
            next
        }
        sec == 3 && NF >= 5 {                            # sinfo: part A/I/O/T nodes mem gres
            split($2, cc, "/"); p = $1; gsub(/[^0-9]/, "", $4)
            ca[p] += cc[1]; ci[p] += cc[2]; ct[p] += cc[4]; nn[p] += $3; mm[p] += $3 * $4 / 1024; gg[p] += $3 * ngpu($5)
        }
        END {
            nacc = split(accts, al, ",")
            for (i = 1; i <= np; i++) { t = pf[order[i], "PriorityTier"] + 0; if (t > maxtier) maxtier = t }
            w = 9; for (i = 1; i <= np; i++) if (length(order[i]) > w) w = length(order[i])
            printf "%-*s %-7s %5s %6s %6s %7s %5s %-13s %-23s %-9s %s\n", w, "PARTITION", "ACCESS", "NODES", "CPUS", "FREE", "MEM", "GPUS", "MAX TIME", "BUSY (cores in use)", "PREEMPT", "OPENED BY"
            shown = 0
            for (pass = 1; pass <= 2; pass++)
                for (i = 1; i <= np; i++) {
                    p = order[i]
                    via = ""
                    for (j = 1; j <= nacc; j++) if (hasall[al[j]] || spec[al[j], p]) via = via (via == "" ? "" : ",") al[j]
                    aa = pf[p, "AllowAccounts"]; if (aa != "" && aa != "ALL") via = inter(via, aa, 1)
                    da = pf[p, "DenyAccounts"];  if (da != "" && da != "(null)") via = inter(via, da, 0)
                    ag = pf[p, "AllowGroups"];   gok = (ag == "" || ag == "ALL" || inter(groups, ag, 1) != "")
                    aq = pf[p, "AllowQos"];      qok = (aq == "" || aq == "ALL" || myqos == "" || inter(myqos, aq, 1) != "")
                    yes = (via != "" && gok && qok)
                    if ((pass == 1) != yes) continue
                    if (!yes && !all) continue
                    st = pf[p, "State"]
                    acc = yes ? ((st == "UP" || st == "") ? col("92", sprintf("%-7s", "yes")) : col("93", sprintf("%-7s", "yes/" tolower(st)))) : col("91", sprintf("%-7s", "no"))
                    mt = pf[p, "MaxTime"]; if (mt == "" || mt == "UNLIMITED") mt = "unlimited"
                    T = ct[p] + 0; A = ca[p] + 0
                    b = (T > 0) ? sprintf("%s %3d%%", bar(A, T, 16), 100 * A / T) : "-"
                    why = yes ? via : (via == "" ? "no account of mine" : !gok ? "group" : "QOS")
                    tier = pf[p, "PriorityTier"]
                    if (tier == "" || pf[p, "PreemptMode"] == "OFF") pre = col("90", sprintf("%-9s", "-"))
                    else if (tier + 0 >= maxtier) pre = col("92", sprintf("%-9s", "safe"))
                    else if (tier * 10 >= maxtier) pre = col("93", sprintf("%-9s", "low"))
                    else pre = col("91", sprintf("%-9s", "EVICTABLE"))
                    printf "%-*s %s %5d %6d %6d %7s %5d %-13s %-23s %s %s\n", w, p, acc, nn[p], T, ci[p], memfmt(mm[p]), gg[p], mt, b, pre, why
                    if (yes) { shown++; print p > ofile }
                }
            printf "%d partition%s open to you; no = not allowed for any of your accounts%s\n", shown, (shown == 1 ? "" : "s"), (all ? "" : "  (mycluster -a lists them)")
            print "PREEMPT: safe = top tier; low = only the very top tier can evict you; EVICTABLE = owner partitions can kill and requeue you (kamiak, class)"
        }'

    # 4b. GPUs: every GPU node that has a partition open to me
    echo; _hdr "GPUs   (nodes with a partition you may use; -a shows every GPU node)"
    { cat "$openf"; echo "---"; scontrol -o show node 2>/dev/null | grep -E '(^| )Gres=[^ ]*gpu'; echo "---"; squeue -h -t R -u "$me" -o "%N %b" 2>/dev/null; } \
    | awk -v all="$all" -v color="$color" -v glim="$(cut -d'|' -f6 <<< "$lim" | grep -v '^-$' | sort -n | head -1)" "$_AWK_BAR$_AWK_TRES"'
        function col(code, s) { return color ? "\033[" code "m" s "\033[0m" : s }
        BEGIN { sec = 1 }
        $0 == "---" { sec++; next }
        sec == 1 { open[$1] = 1; next }
        sec == 3 { if ($1 !~ /[\[,]/ && ngpu($2) > 0) mine[$1] += ngpu($2); next }
        sec == 2 {
            nd = ""; cfg = 0; al = 0; mdl = "?"; gm = ""; st = "?"; pt = ""; g = ""
            for (i = 1; i <= NF; i++) {
                k = $i; sub(/=.*/, "", k); v = $i; sub(/^[^=]*=/, "", v)
                if (k == "NodeName") nd = v
                else if (k == "Gres") g = v
                else if (k == "CfgTRES") cfg = tv(v, "^gres/gpu=") + 0
                else if (k == "AllocTRES") al = tv(v, "^gres/gpu=") + 0
                else if (k == "State") st = v
                else if (k == "Partitions") pt = v
                else if (k == "AvailableFeatures") {
                    nf = split(v, ft, ",")
                    for (j = 1; j <= nf; j++) {
                        if (ft[j] ~ /^[a-z][0-9]+(-[a-z]+)?$/) mdl = toupper(ft[j])
                        if (ft[j] ~ /^(gpu-mem|mem-per-gpu)-/) { gm = ft[j]; sub(/.*-/, "", gm) }
                    }
                }
            }
            if (nd == "") next
            T = (cfg > 0) ? cfg : ngpu(g); if (T <= 0) next
            np = split(pt, pa, ","); via = ""
            for (j = 1; j <= np; j++) if (pa[j] in open) via = via (via == "" ? "" : ",") pa[j]
            if (via == "" && !all) next
            n++; nn[n] = nd; tt[n] = T; aa[n] = (al > T) ? T : al; md[n] = mdl (gm != "" ? " " gm : ""); sts[n] = st; vv[n] = (via == "" ? "(none open)" : via)
            if (length(vv[n]) > vw) vw = length(vv[n])
        }
        END {
            if (n == 0) { print "  no GPU nodes open to you"; exit }
            printf "%-8s %-9s %-14s %4s %5s %4s  %-22s %5s  %s\n", "NODE", "STATE", "GPU", "GPUS", "USED", "FREE", "USAGE", "MINE", "OPEN VIA"
            for (pass = 0; pass <= 1; pass++)
                for (i = 1; i <= n; i++) {
                    bad = (sts[i] ~ /DOWN|DRAIN|FAIL|MAINT|NOT_RESP/)
                    if ((bad ? 1 : 0) != pass) continue
                    fr = bad ? "-" : tt[i] - aa[i]
                    printf "%-8s %-9.9s %-14s %4d %5d %4s  %s %3d%%  %5d  %s\n", nn[i], sts[i], md[i], tt[i], aa[i], fr, bar(aa[i], tt[i], 16), 100 * aa[i] / tt[i], mine[nn[i]] + 0, vv[i]
                    gt += tt[i]; if (!bad) gf += tt[i] - aa[i]; gm2 += mine[nn[i]]
                }
            printf "%d of %d GPUs free on %d nodes; you hold %d", gf, gt, n, gm2
            printf "%s\n", (glim != "" ? sprintf("  (smallest per-account GPU limit: %s)", glim) : "  (no GPU limit set on your accounts)")
        }'
    rm -f "$openf"

    # 5. Usage now
    echo; _hdr "Usage now   (running jobs against the account limits)"
    { sed 's/^/L|/' <<< "$lim"; echo "---"; scontrol -o show job 2>/dev/null | grep "UserId=$me("; } \
    | awk "$_AWK_BAR$_AWK_TRES"'
        BEGIN { sec = 1 }
        $0 == "---" { sec = 2; next }
        sec == 1 {
            split($0, f, "|"); a = f[2]
            if (!(a in seen)) { seen[a] = 1; ord[++n] = a }
            if (cl[a] == "" || cl[a] == "-") cl[a] = f[5]      # f[1] is the "L" marker
            if (ml[a] == "" || ml[a] == "-") ml[a] = f[6]
            if (gl[a] == "" || gl[a] == "-") gl[a] = f[7]
            next
        }
        sec == 2 {
            st = ""; ac = ""; rt = ""; tl = ""; tr = ""; gr = ""; nodes = 0
            for (i = 1; i <= NF; i++) {
                k = $i; sub(/=.*/, "", k); v = $i; sub(/^[^=]*=/, "", v)
                if (k == "JobState") st = v
                else if (k == "Account") ac = v
                else if (k == "RunTime") rt = v
                else if (k == "TimeLimit") tl = v
                else if (k == "TRES" || k == "AllocTRES") tr = v
                else if (k == "TresPerNode" || k == "Gres") gr = v
                else if (k == "NumNodes") nodes = v + 0
            }
            if (!(ac in seen)) { seen[ac] = 1; ord[++n] = ac }
            if (st == "PENDING") { pend[ac]++; next }
            if (st != "RUNNING") next
            cp = tv(tr, "^cpu=") + 0; me2 = gbv(tv(tr, "^mem=")) + 0
            gp = tv(tr, "^gres/gpu(:[^=]*)?=") + 0
            if (gp == 0) gp = ngpu(gr) * (nodes > 0 ? nodes : 1)
            r = secs(rt); L = secs(tl)
            run[ac]++; cpu[ac] += cp; mem[ac] += me2; gpu[ac] += gp
            if (r > mx[ac]) mx[ac] = r
            if (L >= 0 && (!(ac in mn) || L - r < mn[ac])) mn[ac] = L - r
            cph[ac] += cp * r / 3600
        }
        function lt(used, limit, w) { return (limit ~ /^[0-9.]+/) ? sprintf("%d/%d", used, limit + 0) : sprintf("%d/-", used) }
        END {
            printf "%-12s %4s %5s  %-9s %-12s %-10s %-8s %-12s %-12s %s\n", "ACCOUNT", "RUN", "PEND", "CPUS", "(of limit)", "MEM (GB)", "GPUS", "LONGEST RUN", "NEXT ENDS IN", "CPU-H SO FAR"
            for (i = 1; i <= n; i++) {
                a = ord[i]
                b = (cl[a] ~ /^[0-9.]+/ && cl[a] + 0 > 0) ? bar(cpu[a], cl[a] + 0, 10) : ""
                if (b == "") b = sprintf("%12s", "")
                printf "%-12s %4d %5d  %-9s %s %-10s %-8s %-12s %-12s %.1f\n", a, run[a], pend[a], lt(cpu[a], cl[a]), b, lt(mem[a], ml[a]), lt(gpu[a], gl[a]),
                    (run[a] ? dur(mx[a]) : "-"), (run[a] && (a in mn) ? dur(mn[a]) : "-"), cph[a]
                tr_ += run[a]; tp += pend[a]; tc += cpu[a]; tm += mem[a]; tg += gpu[a]; th += cph[a]
            }
            if (n > 1) printf "%-12s %4d %5d  %-9d %12s %-10d %-8d %-12s %-12s %.1f\n", "TOTAL", tr_, tp, tc, "", tm, tg, "", "", th
        }'

    # 6. Usage so far: this month and this year
    echo; _hdr "Usage so far   (this month since $month; year since $year)"
    {
        sreport -n -P -t Hours -T cpu,gres/gpu cluster AccountUtilizationByUser Users="$me" Start="$month" End=now 2>/dev/null \
            | awk -F'|' '$3 != "" { print "M|" $2 "|" $(NF - 1) "|" $NF }'
        sreport -n -P -t Hours -T cpu,gres/gpu cluster AccountUtilizationByUser Users="$me" Start="$year" End=now 2>/dev/null \
            | awk -F'|' '$3 != "" { print "Y|" $2 "|" $(NF - 1) "|" $NF }'
        sacct -u "$me" -X -n -P -S "$month" -E now -o Account,State,ElapsedRaw 2>/dev/null | sed 's/^/J|/'
        sshare -n -P -u "$me" -o Account,User,FairShare 2>/dev/null | awk -F'|' -v me="$me" '$2 == me { gsub(/^ +| +$/, "", $1); print "F|" $1 "|" $3 }'
        sed 's/^/L|/' <<< "$lim"
    } | awk -F'|' "$_AWK_BAR"'
        function add(a) { if (!(a in seen)) { seen[a] = 1; ord[++n] = a } }
        $1 == "L" { add($2) }
        $1 == "M" { add($2); if ($3 == "cpu") mc[$2] += $4; else if ($3 == "gres/gpu") mg[$2] += $4 }
        $1 == "Y" { add($2); if ($3 == "cpu") yc[$2] += $4; else if ($3 == "gres/gpu") yg[$2] += $4 }
        $1 == "J" {
            add($2); jobs[$2]++; wall[$2] += $4 / 3600
            if ($3 ~ /^COMPLETED/) ok[$2]++
            else if ($3 ~ /^(RUNNING|PENDING|REQUEUED|SUSPENDED|COMPLETING)/) live[$2]++
            else bad[$2]++
        }
        $1 == "F" { add($2); fs[$2] = $3 }
        END {
            printf "%-12s %5s %5s %5s %5s %9s %9s %8s   %10s %8s   %s\n", "ACCOUNT", "JOBS", "DONE", "FAIL", "LIVE", "WALL-H", "CPU-H", "GPU-H", "YEAR CPU-H", "GPU-H", "FAIRSHARE (1 = barely used, 0.5 = at share)"
            for (i = 1; i <= n; i++) {
                a = ord[i]
                f = (a in fs && fs[a] ~ /^[0-9.]+$/) ? sprintf("%s %.2f", bar(fs[a] * 100, 100, 10), fs[a]) : "-"
                printf "%-12s %5d %5d %5d %5d %9.1f %9.0f %8.0f   %10.0f %8.0f   %s\n", a, jobs[a], ok[a], bad[a], live[a], wall[a], mc[a], mg[a], yc[a], yg[a], f
                tj += jobs[a]; to += ok[a]; tb += bad[a]; tl += live[a]; tw += wall[a]; tmc += mc[a]; tmg += mg[a]; tyc += yc[a]; tyg += yg[a]
            }
            if (n > 1) printf "%-12s %5d %5d %5d %5d %9.1f %9.0f %8.0f   %10.0f %8.0f\n", "TOTAL", tj, to, tb, tl, tw, tmc, tmg, tyc, tyg
        }'

    # 7. Disk
    echo; _hdr "Disk   (filesystem totals are shared; your own limit is the quota)"
    printf '  %-32s %6s %6s %6s  %s\n' "PATH" "SIZE" "USED" "FREE" "FULL"
    for d in "$HOME" "/scratch/user/$me" /weka/scratch /weka/data; do
        [ -d "$d" ] || continue
        df -Ph "$d" 2>/dev/null | awk -v p="$d" 'NR == 2 { gsub(/%/, "", $5); print p, $2, $3, $4, $5 }' \
        | while read -r p sz us fr pc; do
            printf '  %-32s %6s %6s %6s  %s %s%%\n' "$p" "$sz" "$us" "$fr" "$(_bar "$pc" 100 16)" "$pc"
        done
    done
    if command -v quota >/dev/null 2>&1; then
        quota -s 2>&1 | head -12 | sed "s/^/    /" | { read -r l && { echo "  quota:"; echo "$l"; cat; }; }
    fi
    echo "  scratch workspaces are deleted after 14 days; list them with mydisk"
}

# mynodes  --  status of the nodes in $KAMIAK_MY_NODES (see section 1)
#   One line per node: state, cores total / in use / idle, a usage bar and who
#   is running there. A TOTAL line at the bottom adds them all up.
#   The bar is split by user: ME = white, everyone else = red, green, blue,
#   yellow, magenta, cyan in order of how many cores they hold (see _AWK_UBAR).
#   Cores SLURM says are allocated but that squeue cannot assign to a
#   single-node job (multi-node jobs) show as dark-grey "(other)".
#   Free cores are dim dots. One block is T/20 cores, so on a 128-core node a
#   block is ~6 cores; any user with at least one core still gets one block.
#   NO_COLOR=1 mynodes   -> letters instead of colours (W = me, R, G, B, ...).
#   Without KAMIAK_MY_NODES set, use  nodeson -p <partition>  instead.
mynodes() {
    local nodes
    if [ -z "$KAMIAK_MY_NODES" ]; then
        echo "mynodes: set KAMIAK_MY_NODES first (see section 1), or use nodeson -p $KAMIAK_MY_PART" >&2
        return 1
    fi
    nodes=$(scontrol show hostnames "$KAMIAK_MY_NODES" | paste -sd, -)    # cn[161-167],cn178 -> cn161,...,cn178
    { sinfo -h -N -n "$nodes" -p "$KAMIAK_MY_PART" -o "%N %T %C"; echo "---"; squeue -h -t R -w "$nodes" -o "%N %u %C"; } \
    | awk -v me="$USER" -v plain="${NO_COLOR:-}" -v order="${nodes//,/ }" "$_AWK_UBAR"'
    BEGIN { ub_init(me, plain); n = split(order, ord, " "); sec = 1 }
    $0 == "---" { sec = 2; next }
    sec == 1 && NF >= 3 { split($3, a, "/"); tot[$1] = a[4]; alc[$1] = a[1]; st[$1] = $2 }   # node state A/I/O/T
    sec == 2 && NF >= 3 && ($1 in tot) { ub_add($1, $2, $3) }    # multi-node jobs ("cn[..]") fall through to (other)
    END {
        ub_assign()
        printf "%-8s %-10s %6s %6s %6s  %-22s %4s  %s\n", "NODE", "STATE", "TOTAL", "ALLOC", "IDLE", "USAGE", "", "USER(S) (cpus)"
        gt = 0; ga = 0
        for (k = 1; k <= n; k++) {
            nd = ord[k]; T = tot[nd] + 0; A = alc[nd] + 0
            if (T == 0) { printf "%-8s ?\n", nd; continue }
            b = ub_draw(nd, T, A, 20)
            printf "%-8s %-10s %6d %6d %6d  %s %3d%%  %s\n", nd, st[nd], T, A, T - A, b, int(A * 100 / T + 0.5), ub_leg
            gt += T; ga += A
        }
        if (gt > 0) printf "%-8s %-10s %6d %6d %6d  %.0f%% allocated\n", "TOTAL", "", gt, ga, gt - ga, ga * 100 / gt
        ub_key(12)
    }'
}

# hwnodes [partition]  --  what hardware each node has
#   Example:  hwnodes            ($KAMIAK_MY_PART)
#             hwnodes kamiak
#   Columns: node, CPU cores, memory in MB, GPUs ("gres"; "(null)" = none).
hwnodes() {
    local part=${1:-$KAMIAK_MY_PART}
    printf "%-8s %5s %10s  %s\n" NODE CPUS MEM_MB GRES
    sinfo -h -N -p "$part" -o "%N %c %m %G" | sort -u | awk '{printf "%-8s %5s %10s  %s\n", $1, $2, $3, $4}'
}

# nodeinfo [-n] <node> [node ...]  --  `scontrol show node`, made readable
#
#   Example:  nodeinfo sn14
#             nodeinfo sn[16-18] cn161      (SLURM node ranges work)
#             nodeinfo -n sn17              (-n = hide other people's usernames)
#   One block per node: state (and the reason if it is down or drained), the
#   partitions it is in, CPU model, cores, memory and GPUs as "in use / total"
#   with a bar, local disk, load, uptime, and the jobs running on it.
#   "OS free" memory is what Linux reports; it is often low on an idle node
#   because the file cache counts as used. "Allocated" is what SLURM has handed
#   out to jobs, and is the number that decides whether a job fits.
#   Colours only on a terminal and when NO_COLOR is not set.
nodeinfo() {
    local anon="" opt OPTIND=1 list n color=""
    while getopts "n" opt; do
        case "$opt" in
            n) anon=1 ;;
            *) echo "Usage: nodeinfo [-n] <node> [node ...]" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    if [ $# -eq 0 ]; then
        echo "Usage: nodeinfo [-n] <node> [node ...]    e.g.  nodeinfo sn14   nodeinfo sn[16-18]" >&2
        return 1
    fi
    list=$(scontrol show hostnames "$(IFS=,; echo "$*")" 2>/dev/null)
    if [ -z "$list" ]; then echo "nodeinfo: no such node(s): $*" >&2; return 1; fi
    [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && color=1
    for n in $list; do
        { scontrol -o show node "$n" 2>/dev/null; echo "---"
          squeue -h -t R -w "$n" -o "%i|%u|%C|%b|%M|%D|%j" 2>/dev/null; } \
        | awk -v me="$USER" -v anon="$anon" -v color="$color" -v want="$n" "$_AWK_BAR"'
            function c(code, s) { return color ? "\033[" code "m" s "\033[0m" : s }
            function gb(mb) { return sprintf("%.0f GB", mb / 1024) }
            function gpus(s,   k, i, it, t, typed) {    # gres/gpu=N out of a TRES list
                t = -1; typed = 0; k = split(s, it, ",")
                for (i = 1; i <= k; i++) {
                    if (it[i] ~ /^gres\/gpu=/) { sub(/.*=/, "", it[i]); return it[i] + 0 }
                    if (it[i] ~ /^gres\/gpu:/) { sub(/.*=/, "", it[i]); typed += it[i]; t = typed }
                }
                return (t < 0) ? 0 : t
            }
            function cpuname(t,   f, k, nm, fam) {      # gold-6238r-2.20ghz -> Xeon Gold 6238R @ 2.20 GHz
                f = t; sub(/^.*-/, "", f); sub(/ghz$/, "", f)
                nm = t; sub(/-[0-9.]+ghz$/, "", nm)
                k = split(nm, p, "-"); fam = p[1]
                if (fam ~ /^(gold|platinum|silver|bronze)$/) nm = "Xeon " toupper(substr(fam, 1, 1)) substr(fam, 2) " " toupper(substr(nm, length(fam) + 2))
                else if (fam ~ /^e[357]$/) nm = "Xeon " toupper(fam) "-" toupper(p[2]) (k > 2 ? " " p[3] : "")
                else nm = toupper(nm)
                return nm " @ " f " GHz"
            }
            BEGIN {
                split("haswell Haswell broadwell Broadwell skylake Skylake cascadelake Cascade_Lake icelake Ice_Lake sapphirerapids Sapphire_Rapids emeraldrapids Emerald_Rapids graniterapids Granite_Rapids", g, " ")
                for (i = 1; i in g; i += 2) { gen[g[i]] = g[i + 1]; gsub(/_/, " ", gen[g[i]]) }
                sec = 1
            }
            $0 == "---" { sec = 2; next }
            sec == 1 {
                line = $0
                for (i = 1; i <= NF; i++) {
                    if ($i !~ /^[A-Za-z]+=/) continue
                    k = $i; sub(/=.*/, "", k); v = $i; sub(/^[^=]*=/, "", v); f[k] = v
                }
                if (match(line, /Reason=.*/)) f["Reason"] = substr(line, RSTART + 7)
                next
            }
            sec == 2 && NF { jobs[++nj] = $0 }
            END {
                if (f["NodeName"] == "") { printf "nodeinfo: no data for %s\n", want; exit }
                st = f["State"]
                sc = (st ~ /DOWN|DRAIN|FAIL|MAINT|NOT_RESP/) ? "1;91" : (st ~ /^IDLE/) ? "92" : (st ~ /^MIX/) ? "93" : "91"
                pt = f["Partitions"]; gsub(/,/, ", ", pt)
                printf "%s  %s   partitions: %s\n", c("1;97", f["NodeName"]), c(sc, st), pt
                if (f["Reason"] != "") printf "  %-9s %s\n", "Reason", c("91", f["Reason"])

                nf = split(f["AvailableFeatures"], ft, ",")
                cpu = "?"; g1 = ""; isa = ""; gm = ""; gname = ""; garch = ""
                for (j = 1; j <= nf; j++) {
                    if (ft[j] in gen) g1 = gen[ft[j]]
                    else if (ft[j] ~ /ghz$/) cpu = cpuname(ft[j])
                    else if (ft[j] == "avx-512") isa = "AVX-512"
                    else if (ft[j] == "avx2" && isa == "") isa = "AVX2"
                    else if (ft[j] ~ /^[a-z][0-9]+(-[a-z]+)?$/) gname = toupper(ft[j])
                    else if (ft[j] ~ /^(gpu-mem|mem-per-gpu)-/) { gm = ft[j]; sub(/.*-/, "", gm); sub(/GB$/, " GB", gm) }
                    else if (ft[j] ~ /^(ampere|hopper|volta|ada|blackwell)$/) garch = toupper(substr(ft[j], 1, 1)) substr(ft[j], 2)
                }
                ct = f["CPUTot"] + 0; ca = f["CPUAlloc"] + 0
                printf "  %-9s %s%s%s\n", "CPU", (cpu == "?" ? "model not listed" : cpu), (g1 != "" ? ", " g1 : ""), (isa != "" ? ", " isa : "")
                bad = (st ~ /DOWN|DRAIN|FAIL|MAINT|NOT_RESP/)
                printf "  %-9s %s  %d / %d in use, %d idle%s\n", "Cores", bar(ca, ct, 20), ca, ct, ct - ca,
                    (f["Sockets"] > 0 ? sprintf("   (%d sockets x %d cores)", f["Sockets"], f["CoresPerSocket"]) : "")

                mr = f["RealMemory"] + 0; ma = f["AllocMem"] + 0
                printf "  %-9s %s  %s / %s allocated, %s free for jobs%s\n", "Memory", bar(ma, mr, 20), gb(ma), gb(mr), gb(mr - ma),
                    (f["FreeMem"] != "" ? "   (OS free: " gb(f["FreeMem"]) ")" : "")

                gt = gpus(f["CfgTRES"]); ga = gpus(f["AllocTRES"])
                if (gt == 0 && f["Gres"] ~ /gpu/) { gt = f["Gres"]; sub(/\(.*/, "", gt); sub(/.*:/, "", gt); gt += 0 }
                if (gt > 0)
                    printf "  %-9s %s  %d / %d in use, %s   (%d x %s%s%s)\n", "GPUs", bar(ga, gt, 20), ga, gt,
                        (bad ? c("91", "node unavailable") : gt - ga > 0 ? c("92", (gt - ga) " free") : c("91", "none free")), gt, (gname != "" ? gname : "GPU"),
                        (gm != "" ? " " gm : ""), (garch != "" ? ", " garch : "")
                else
                    printf "  %-9s none\n", "GPUs"

                o = ""
                if (f["TmpDisk"] > 0)     o = o ", " gb(f["TmpDisk"]) " local /tmp"
                if (f["CPULoad"] != "")   o = o ", load " f["CPULoad"]
                if (f["BootTime"] != "")  o = o ", up since " substr(f["BootTime"], 1, 10)
                if (o != "") printf "  %-9s %s\n", "Other", substr(o, 3)

                if (nj == 0) { printf "  %-9s none running\n", "Jobs"; print ""; exit }
                printf "  %-9s %d running\n", "Jobs", nj
                for (j = 1; j <= nj; j++) {
                    split(jobs[j], q, "|")
                    u = q[2]; if (anon && u != me) u = "(other)"
                    gr = (q[4] == "(null)" || q[4] == "") ? "-" : q[4]
                    printf "            %-10s %-16s %4s cpus  %-14s %11s  %s%s\n", q[1], (u == me ? c("1;97", u) : u), q[3], gr, q[5], q[7], (q[6] + 0 > 1 ? "  (" q[6] " nodes)" : "")
                }
                print ""
            }'
    done
}


# =============================================================================
# 5. Submitting to my partition (my nodes only)
# =============================================================================

# _mine_opts NAME [sbatch args...]  --  fill _MINE_OPTS with the partition and
#   --exclude options that keep a job on $KAMIAK_MY_NODES. Used by sbmine and
#   ijob. The exclude list is built fresh from SLURM each time, so new or
#   renamed nodes in the partition are excluded too.
#   Refuses (returns 1) if the caller's own options would override those, or if
#   SLURM can't list the partition, rather than risk landing on someone else's
#   node. Options are checked up to the first argument that is an existing file
#   (the job script); anything after it belongs to the script.
_mine_opts() {
    local who=$1 a all ex
    shift
    for a in "$@"; do
        [ -f "$a" ] && break
        case "$a" in
            -p|-p?*|--partition|--partition=*|-x|-x?*|--exclude|--exclude=*)
                echo "$who: don't pass $a here; it would override the partition / exclude list $who sets. Use plain sbatch for that." >&2
                return 1 ;;
        esac
    done
    _MINE_OPTS=(-p "$KAMIAK_MY_PART")
    [ -z "$KAMIAK_MY_NODES" ] && return 0
    all=$(sinfo -h -N -p "$KAMIAK_MY_PART" -o "%N" 2>/dev/null | sort -u)
    if [ -z "$all" ]; then
        echo "$who: could not list the nodes in $KAMIAK_MY_PART; NOT submitting" >&2
        return 1
    fi
    ex=$(comm -23 <(echo "$all") <(scontrol show hostnames "$KAMIAK_MY_NODES" | sort -u) | paste -sd, -)
    [ -n "$ex" ] && _MINE_OPTS+=(--exclude="$ex")
    return 0
}

# sbmine  --  sbatch onto $KAMIAK_MY_PART, and only onto $KAMIAK_MY_NODES if set
#
#   Use this INSTEAD OF plain `sbatch -p <part>`. All other sbatch options work.
#     sbmine job.sbatch                -> runs on any one of my nodes
#     sbmine -w cn163 job.sbatch       -> runs on cn163 specifically
#
#   How it works: it tells SLURM to avoid every node that is NOT mine
#   (--exclude), rather than listing my nodes. Listing them with --nodelist
#   would not work: sbatch reads --nodelist as "the job must use ALL of these
#   nodes", so a one-node job would be rejected.
#   Note: #SBATCH -p / --exclude lines inside the script are overridden by
#   these command-line options.
sbmine() {
    _mine_opts sbmine "$@" || return 1
    sbatch "${_MINE_OPTS[@]}" "$@"
}


# =============================================================================
# 6. Storage and scratch workspaces
# =============================================================================
# Scratch workspaces live under /scratch/user/$USER and are DELETED after
# 14 days. Run big jobs there; copy results you want to keep back to $HOME
# or /weka/data.

# mkws <name>  --  make a new scratch workspace and cd into it
#   Example:  mkws md_run3
#             -> /scratch/user/$USER/md_run3_<date>_<time>
#   Names may contain letters, digits, _ . and - only.
mkws() {
    if [ -z "$1" ] || [[ $1 == -* ]] || [[ $1 =~ [^A-Za-z0-9_.-] ]]; then
        echo "Usage: mkws <name>   (letters, digits, _ . - only)" >&2
        return 1
    fi
    mkworkspace -n "$1" || return
    # mkworkspace doesn't print the new path, so find the newest
    # "<name>_<date>..." folder. The [0-9] stops "run" matching "run_big_...".
    local ws
    ws=$(ls -dt /scratch/user/"$USER/$1"_[0-9]* 2>/dev/null | head -1)
    if [ -z "$ws" ]; then
        echo "mkws: created, but could not find the new folder; run lsworkspace" >&2
        return 1
    fi
    cd "$ws" && echo "now in $ws"
}

# cdws  --  cd into my most recently used scratch workspace
cdws() {
    local ws
    ws=$(ls -dt /scratch/user/"$USER"/*/ 2>/dev/null | head -1)
    if [ -z "$ws" ]; then echo "cdws: no workspaces found" >&2; return 1; fi
    cd "$ws" && pwd
}

# mydisk [-u]  --  how much disk space do I have?
#   Shows free space on home, scratch and data, my quota, and my scratch
#   workspaces (with days left before they expire).
#   mydisk -u   also measures the size of $HOME. This can take minutes when
#               there are many small files, so it is off by default.
#   (/scratch/user and /weka/scratch are both listed in case they are not the
#    same filesystem; if they show identical numbers, they are.)
mydisk() {
    echo "== Filesystems =="
    df -h --output=size,used,avail,pcent,target "$HOME" /scratch/user/"$USER" /weka/scratch /weka/data 2>/dev/null
    echo
    echo "== Quota =="
    if command -v quota >/dev/null 2>&1; then quota -s 2>&1 | head -20; else echo "  quota: not installed"; fi
    if command -v lsworkspace >/dev/null 2>&1; then echo; echo "== Scratch workspaces =="; lsworkspace; fi
    if [ "$1" = "-u" ]; then
        echo
        echo "== My usage =="
        du -sh "$HOME" 2>/dev/null | sed 's/^/  /'
    fi
}


# =============================================================================
# 7. Running and checking jobs
# =============================================================================

# ijob [cores] [time]  --  interactive shell on $KAMIAK_MY_PART
#   For testing, compiling or debugging on a compute node instead of the
#   login node. Like sbmine, it stays on $KAMIAK_MY_NODES when that is set.
#     ijob                -> 8 cores for 1 hour
#     ijob 32 4:00:00     -> 32 cores for 4 hours
#   Type `exit` to give the node back.
ijob() {
    _mine_opts ijob || return 1
    srun "${_MINE_OPTS[@]}" -N1 -c "${1:-8}" --time="${2:-1:00:00}" --pty bash -l
}

# jobinfo <jobid>  --  how did a job go?
#   Shows state (COMPLETED, FAILED, TIMEOUT, OUT_OF_MEMORY, ...), run time, CPU
#   time, peak memory (MaxRSS) and exit code, then `seff`'s efficiency summary
#   if seff is installed.
#   Tip: use peak memory to pick a sensible --mem for the next similar job.
jobinfo() {
    if [ -z "$1" ]; then echo "Usage: jobinfo <jobid>" >&2; return 1; fi
    sacct -j "$1" --format=JobID%18,JobName%20,State%12,Elapsed,TotalCPU,AllocCPUS,MaxRSS,ExitCode | _jobcol 3 2
    if command -v seff >/dev/null 2>&1; then echo; seff "$1"; fi
}

# myhist [days]  --  my jobs from the last few days (default 3), one line each
#   Example:  myhist 7
#   Handy for finding a job ID you have lost, or spotting what failed.
myhist() {
    sacct -u "$USER" -S "$(date -d "-${1:-3} days" +%F)" -X \
        --format=JobID%12,JobName%24,Partition%8,State%12,Elapsed,AllocCPUS,NodeList%14,ExitCode | _jobcol 4 2
}

# mystart  --  when does SLURM expect my pending jobs to start?
#   Estimates only; they change as other jobs finish early or new ones arrive.
mystart() { squeue -u "$USER" -t PD --start | _jobcol 5; }

# tailjob <jobid>  --  watch a running job's output as it is written
#   Finds the job's output file from SLURM, so you don't need to know its name.
#   Press Ctrl-C to stop watching (the job keeps running).
tailjob() {
    local f
    f=$(scontrol show job "$1" 2>/dev/null | sed -n 's/^ *StdOut=//p')
    if [ -z "$f" ]; then echo "tailjob: no StdOut for job '$1'" >&2; return 1; fi
    tail -f "$f"
}



# =============================================================================
# 8. Shell history
# =============================================================================
HISTSIZE=50000                 # commands kept in memory for this shell
HISTFILESIZE=100000            # commands kept in ~/.bash_history
HISTTIMEFORMAT='%F %T  '       # `history` shows the date and time of each command
HISTCONTROL=ignoreboth         # skip duplicates and commands starting with a space
shopt -s histappend            # add to the history file instead of overwriting it,
                               # so several open terminals don't erase each other


# =============================================================================
# 9. Directory tree helper
# =============================================================================
# ktree: pretty directory tree (Kamiak has no `tree`).
#   usage: ktree [dir] [depth] [s]     depth default 3; add `s` as 3rd arg for folder sizes (slower)
#   shows directories only, with the number of files directly inside each; colours only on a terminal
_ktree_rec() {   # dir prefix depth max sizes
  local dir="$1" prefix="$2" depth="$3" max="$4" sz="$5"
  [ "$depth" -ge "$max" ] && return
  local -a subs=()
  local e
  for e in "$dir"/*/; do
    [ -d "$e" ] && [ ! -L "${e%/}" ] && subs+=("${e%/}")
  done
  local n=${#subs[@]} i=0 name conn ext cnt size cb ce cd
  if [ -t 1 ]; then cb=$'\033[1;34m'; cd=$'\033[2m'; ce=$'\033[0m'; else cb=""; cd=""; ce=""; fi
  for e in "${subs[@]}"; do
    i=$((i + 1)); name=${e##*/}
    if [ "$i" -eq "$n" ]; then conn="└── "; ext="    "; else conn="├── "; ext="│   "; fi
    cnt=$(find "$e" -maxdepth 1 -type f 2>/dev/null | wc -l)
    printf '%s%s%s%s%s' "$prefix" "$conn" "$cb" "$name" "$ce"
    [ "$cnt" -gt 0 ] && printf ' %s(%d file%s)%s' "$cd" "$cnt" "$([ "$cnt" -eq 1 ] || echo s)" "$ce"
    if [ -n "$sz" ]; then size=$(du -sh "$e" 2>/dev/null | cut -f1); printf ' %s[%s]%s' "$cd" "$size" "$ce"; fi
    printf '\n'
    _ktree_rec "$e" "$prefix$ext" $((depth + 1)) "$max" "$sz"
  done
}
ktree() {
  local d="${1:-.}" n="${2:-3}" sz=""
  [ "${3:-}" = "s" ] && sz=1
  [ -d "$d" ] || { echo "ktree: not a directory: $d" >&2; return 1; }
  if [ -t 1 ]; then printf '\033[1;36m%s\033[0m\n' "$d"; else printf '%s\n' "$d"; fi
  _ktree_rec "${d%/}" "" 0 "$n" "$sz"
}

