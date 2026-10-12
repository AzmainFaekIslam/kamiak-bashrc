"""Generate the TikZ for the figures that have one shape per compute node.

Writes figs/system.tex (the full schematic) and figs/strip.tex (the partition
strip). Run before compiling main.tex; compile.sh does both.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(HERE, "figs"), exist_ok=True)


# ----------------------------------------------------------------------------
# Rack contents, top to bottom.  Kinds: n = 64-core-or-smaller node,
# big = 128-core node, gpu = 1U GPU node, gpu2u = 2U GPU server.
# Node counts come from hpc.wsu.edu/kamiak-hpc/queue-list (Oct 2026) and
# `sinfo -p popov` (Jun 2026).  "others" = 146 minus the published partitions.
# ----------------------------------------------------------------------------
RACKS = [
    ("popov", "21 nodes", [("n", 15), ("big", 6)], True),
    ("cas", "13 nodes", [("gpu", 1), ("n", 12)], True),
    ("vcea", "4 nodes", [("gpu", 1), ("n", 3)], True),
    ("camas", "3 nodes", [("gpu2u", 3)], True),
    ("coe", "1 node", [("n", 1)], False),
    (None, None, [("gpu", 1), ("n", 34)], False),
    (None, None, [("n", 35)], False),
    (None, None, [("n", 34)], False),
]
FILL = {"n": "slab", "big": "slabbig", "gpu": "slabgpu", "gpu2u": "slabgpu"}


def system():
    o = []
    A = o.append
    A(r"\begin{tikzpicture}[x=1cm,y=1cm,font=\sffamily\scriptsize]")

    # zone titles
    for x, t in [(0, "OUTSIDE"), (3.8, "HEAD NODES \\textperiodcentered{} 4 VIRTUAL MACHINES"),
                 (9.0, "WEKA STORAGE \\textperiodcentered{} 1\\,PB NVMe"), (14.2, "ARCHIVE \\& TRANSFER")]:
        A(rf"\node[zone,anchor=south west] at ({x},12.65) {{{t}}};")

    # outside
    A(r"\node[box,minimum width=3cm,minimum height=1.6cm,anchor=north west] (laptop) at (0,12.5) {};")
    A(r"\node[title,anchor=north] at (1.5,12.3) {Your laptop};")
    A(r"\node[sub,anchor=north] at (1.5,11.85) {\ttfamily opkssh login kamiak};")
    A(r"\node[sub,anchor=north] at (1.5,11.45) {Okta, once a day};")
    A(r"\node[box,minimum width=3cm,minimum height=1.9cm,anchor=north west] (globus) at (0,10.5) {};")
    A(r"\node[title,anchor=north] at (1.5,10.3) {Globus};")
    A(r"\node[sub,anchor=north,align=center] at (1.5,9.85) {\ttfamily wsuhpc\#kamiak\\[1pt]read-only: /data, /archive\\read-write: /scratch\\no /home};")

    # head nodes
    A(r"\draw[group] (3.8,8.6) rectangle (8.7,12.6);")
    A(r"\node[box,minimum width=2.15cm,minimum height=1.6cm,anchor=north west] (login) at (4.0,12.25) {};")
    A(r"\node[title,anchor=north] at (5.075,12.05) {Login nodes};")
    A(r"\node[sub,anchor=north,align=center] at (5.075,11.6) {you land here\\edit and submit};")
    A(r"\node[box,minimum width=2.05cm,minimum height=1.6cm,anchor=north west] (slurm) at (6.45,12.25) {};")
    A(r"\node[title,anchor=north] at (7.475,12.05) {Slurm};")
    A(r"\node[sub,anchor=north,align=center] at (7.475,11.6) {queue, fairshare\\preemption};")
    A(r"\node[sub,anchor=north west,align=left] at (4.0,10.35) {Internet access: yes\\No jobs or installs here:\\use \texttt{sbatch} or \texttt{idev}};")

    # storage: illustrative servers with drive bays, then the mounts
    A(r"\draw[group] (9.0,8.6) rectangle (13.6,12.6);")
    for i in range(4):
        y = 12.3 - i * 0.36
        A(rf"\draw[server] (9.2,{y - 0.28:.2f}) rectangle (13.4,{y:.2f});")
        for j in range(14):
            x = 9.32 + j * 0.24
            A(rf"\fill[bay] ({x:.2f},{y - 0.22:.2f}) rectangle ({x + 0.17:.2f},{y - 0.06:.2f});")
        A(rf"\fill[ledc] (13.22,{y - 0.14:.2f}) circle (0.045);")
    for i, (p, d) in enumerate([("/home", "100\\,GB per user \\textperiodcentered{} snapshots"),
                                ("/data/lab", "500\\,GB per PI \\textperiodcentered{} snapshots"),
                                ("/scratch", "10\\,TB per user \\textperiodcentered{} 2-week life")]):
        y = 10.55 - i * 0.48
        A(rf"\node[anchor=west,font=\ttfamily\scriptsize\bfseries] at (9.2,{y:.2f}) {{{p}}};")
        A(rf"\node[sub,anchor=west] at (10.75,{y:.2f}) {{{d}}};")
    A(r"\node[sub,anchor=west] at (9.2,8.9) {same files on every node};")

    # archive + dtn
    A(r"\node[box,dashedbox,minimum width=3.2cm,minimum height=1.6cm,anchor=north west] at (14.2,12.5) {};")
    A(r"\node[anchor=north,font=\ttfamily\footnotesize\bfseries] at (15.8,12.3) {/archive};")
    A(r"\node[sub,anchor=north,align=center] at (15.8,11.85) {rented cold storage\\on login + dtn only};")
    A(r"\draw[plain] (15.8,10.9) -- (15.8,10.3);")
    A(r"\node[box,minimum width=3.2cm,minimum height=1.7cm,anchor=north west] at (14.2,10.3) {};")
    A(r"\node[title,anchor=north] at (15.8,10.1) {\yours\,dtn};")
    A(r"\node[sub,anchor=north,align=center] at (15.8,9.65) {data-transfer partition\\big copies as jobs};")

    # fabric
    A(r"\fill[crimson] (3.6,7.5) rectangle (17.4,8.0);")
    A(r"\node[font=\ttfamily\scriptsize\bfseries,text=white,anchor=west] at (9.0,7.75) {InfiniBand HDR100 \textperiodcentered{} 100\,Gb/s \textperiodcentered{} storage I/O and MPI};")
    for x in (5.0, 15.8):
        A(rf"\draw[ib] ({x},8.6) -- ({x},8.0);")
    A(r"\draw[ib,line width=3pt] (11.3,8.6) -- (11.3,8.0);")

    # compute zone
    A(r"\draw[group,dashed] (3.6,0) rectangle (17.4,7.1);")
    A(r"\node[sub,anchor=south west,text=ink] at (3.75,0.08) {\yours\,\textbf{kamiak} (backfill): all 146 compute nodes \textperiodcentered{} jobs here can be preempted};")
    A(r"\node[sub,anchor=south east] at (17.25,0.08) {compute nodes: no outside internet};")
    pitch, sh, top = 0.145, 0.10, 5.85
    for k, (name, sub, slabs, yours) in enumerate(RACKS):
        x = 3.9 + k * 1.68
        A(rf"\draw[rack] ({x:.2f},0.55) rectangle ({x + 1.4:.2f},6.0);")
        A(rf"\draw[ib] ({x + 0.12:.2f},7.5) -- ({x + 0.12:.2f},6.0);")
        y = top
        for kind, n in slabs:
            for _ in range(n):
                h = 0.25 if kind == "gpu2u" else sh
                A(rf"\fill[{FILL[kind]}] ({x + 0.15:.2f},{y - h:.3f}) rectangle ({x + 1.25:.2f},{y:.3f});")
                if kind.startswith("gpu"):
                    A(rf"\fill[white] ({x + 1.05:.2f},{y - h + 0.02:.3f}) rectangle ({x + 1.18:.2f},{y - 0.02:.3f});")
                y -= (h + 0.05) if kind == "gpu2u" else pitch
        if name:
            dot = r"\yours\," if yours else ""
            A(rf"\node[title,anchor=south west,fill=white] at ({x + 0.22:.2f},6.45) {{{dot}{name}}};")
            A(rf"\node[sub,anchor=south west,fill=white] at ({x + 0.22:.2f},6.12) {{{sub}}};")
        if name == "popov":
            A(rf"\node[sub,anchor=north,align=center] at ({x + 0.7:.2f},{y - 0.1:.2f}) {{bottom 6:\\128-core\\Granite\\Rapids}};")
    A(r"\node[title,anchor=south west,fill=white] at (12.46,6.45) {other investor partitions};")
    A(r"\node[sub,anchor=south west,fill=white] at (12.46,6.12) {\yours\,beckman, yan, \dots{} \textperiodcentered{} 104 nodes};")

    # job path
    A(r"\draw[net,-{Stealth[length=5pt]}] (3.0,11.7) -- (4.0,11.7);")
    A(r"\node[jobstep] at (3.5,12.05) {1};")
    A(r"\node[sub] at (3.5,11.35) {ssh};")
    A(r"\draw[ctl,-{Stealth[length=5pt]}] (6.15,11.45) -- (6.45,11.45);")
    A(r"\node[jobstep] at (6.3,12.45) {2};")
    A(r"\draw[ctl,dashed,-{Stealth[length=5pt]}] (7.6,10.65) -- (7.6,6.95);")
    A(r"\node[jobstep] at (7.6,9.6) {3};")
    A(r"\node[sub,anchor=west,fill=white,inner sep=1pt] at (7.7,7.2) {starts job};")
    A(r"\node[jobstep] at (11.7,8.42) {4};")
    A(r"\draw[net,-{Stealth[length=5pt]}] (3.0,9.0) -- (3.4,9.0) -- (3.4,8.18) -- (12.8,8.18) -- (12.8,8.6);")
    A(r"\node[jobstep] at (10.2,8.18) {5};")

    # key
    A(r"\node[zone,anchor=west] at (0,6.6) {KEY};")
    ky = 6.1
    for draw, label in [
        (r"\draw[net] (0,{y}) -- (0.7,{y});", "outside network"),
        (r"\draw[ib] (0,{y}) -- (0.7,{y});", "InfiniBand cable"),
        (r"\draw[ctl,dashed] (0,{y}) -- (0.7,{y});", "Slurm control"),
        (r"\fill[slab] (0,{y0}) rectangle (0.7,{y1});", "compute node"),
        (r"\fill[slabbig] (0,{y0}) rectangle (0.7,{y1});", "128-core node"),
        (r"\fill[slabgpu] (0,{y0}) rectangle (0.7,{y1});", "GPU node"),
        (r"\node at (0.35,{y}) {{\yours}};", "in your login banner"),
        (r"\node[jobstep] at (0.35,{y}) {{1}};", "steps of one job"),
    ]:
        A(draw.format(y=f"{ky:.2f}", y0=f"{ky - 0.05:.2f}", y1=f"{ky + 0.05:.2f}"))
        A(rf"\node[sub,anchor=west] at (0.9,{ky:.2f}) {{{label}}};")
        ky -= 0.48
    A(r"\end{tikzpicture}")
    return "\n".join(o)


def strip():
    """146 bars in partition order; owner brackets above, kamiak bracket below."""
    groups = [  # name, [(kind, n)], yours
        ("popov", [("n", 15), ("big", 6)], True),
        ("cas", [("gpu", 1), ("n", 12)], True),
        ("vcea", [("gpu", 1), ("n", 3)], True),
        ("camas", [("gpu", 3)], True),
        ("coe", [("n", 1)], False),
        ("other investors (beckman, yan, …)", [("gpu", 1), ("n", 103)], False),
    ]
    w = 17.4 / 146
    o = [r"\begin{tikzpicture}[x=1cm,y=1cm,font=\sffamily\scriptsize]"]
    A = o.append
    i = 0
    for name, parts, yours in groups:
        start = i
        for kind, n in parts:
            for _ in range(n):
                x = i * w
                fill = {"n": "stripyou" if yours else "stripother", "big": "stripyoubig",
                        "gpu": "stripyou" if yours else "stripother"}[kind]
                A(rf"\fill[{fill}] ({x + 0.012:.3f},0) rectangle ({x + w - 0.012:.3f},1);")
                if kind == "gpu":
                    A(rf"\fill[ink] ({x + w / 2:.3f},1.17) circle (0.045);")
                i += 1
        x0, x1 = start * w, i * w
        if name.startswith("other"):
            A(rf"\draw[bracket] ({x0 + 0.02:.3f},1.32) -- ({x0 + 0.02:.3f},1.42) -- ({x1 - 0.02:.3f},1.42) -- ({x1 - 0.02:.3f},1.32);")
            A(rf"\node[title,anchor=south] at ({(x0 + x1) / 2:.3f},1.45) {{\yours\,beckman \textcolor{{wsugray}}{{and other investor partitions}} \textperiodcentered{{}} 104 nodes}};")
            continue
        A(rf"\draw[bracket] ({x0 + 0.02:.3f},1.32) -- ({x0 + 0.02:.3f},1.42) -- ({x1 - 0.02:.3f},1.42) -- ({x1 - 0.02:.3f},1.32);")
        mid = (x0 + x1) / 2
        dot = r"\yours\," if yours else ""
        lab = rf"{{{dot}{name} \textcolor{{wsugray}}{{{i - start}}}}}"
        elbow = {"camas": 2.45, "coe": 1.98}.get(name)
        if name in ("popov", "cas"):
            A(rf"\node[title,anchor=south] at ({mid:.3f},1.45) {lab};")
        elif name == "vcea":
            A(rf"\draw[leader] ({mid:.3f},1.42) -- ({mid:.3f},2.33);")
            A(rf"\node[title,anchor=south] at ({mid:.3f},2.35) {lab};")
        else:   # leader up, then right, into the free space before the "others" label
            A(rf"\draw[leader] ({mid:.3f},1.42) -- ({mid:.3f},{elbow}) -- (5.6,{elbow});")
            A(rf"\node[title,anchor=west] at (5.62,{elbow}) {lab};")
    # kamiak bracket below
    A(r"\draw[bracketc] (0.02,-0.12) -- (0.02,-0.24) -- (17.38,-0.24) -- (17.38,-0.12);")
    A(r"\node[title,anchor=north] at (8.7,-0.3) {\yours\,kamiak \textcolor{wsugray}{\textperiodcentered{} backfill \textperiodcentered{} every one of the 146 nodes \textperiodcentered{} preemptable}};")
    A(r"\end{tikzpicture}")
    return "\n".join(o)


open(os.path.join(HERE, "figs", "system.tex"), "w").write(system())
open(os.path.join(HERE, "figs", "strip.tex"), "w").write(strip())
print("figs written")
