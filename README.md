# keeling.earth.illinois.edu — Start Jupyter Lab on a Slurm compute node (single SRUN).
Writes `~/.jlab/<session>_<stamp>.{log,url,port,node,where,tunnel}`
WAITS to print SSH commands + Jupyter URL until NODE and PORT are ready.

 KEY=VALUE (any order):
   hours=2 session=jlab cpus=8 mem=32G partition=seseml jlab_port=8888 [dask_port=8787]

Behavior knobs (env vars):
-   READY_WAIT=0   # seconds to wait here for NODE+PORT; 0 = wait indefinitely (default)
-   PRINT_POLL=1   # polling interval (seconds) while waiting; default 1
-   BASTION=       # optional ProxyJump host, e.g. bastion.illinois.edu (adds -J to OUTER ssh)
