# keeling.earth.illinois.edu — Start Jupyter Lab on a Slurm compute node (single SRUN).
Writes `~/.jlab/<session>_<stamp>.{log,url,port,node,where,tunnel}`
WAITS to print SSH commands + Jupyter URL until NODE and PORT are ready.

## Quickstart:

### Install:
```
git clone https://github.com/atmsillinois/jlab-slurm-screen
chmod u+x jlab-slurm-screen
```
You may wish to consider adding this folder to your path.

### Running
```
cd /path/to/jlab-slurm-screen/
./jlab-slurm-screen.sh hours=2 session=jlab cpus=4 mem=8G jlab_port=5678
```

### Arguments (any order):


| hours=2   |   time of job in hours |
|session=jlab |  prefix of slurm job  |
|cpus=4     |   number of cores     | 
|mem=8G     |   memory per core    |
|partition=seseml   |   slurm partition  |
|jlab_port=8888     |   jupyerlab port to try (may change if not available)   | 
|dask_port=8787     |   [optional] second port to tunnel (i.e., for dask dashboard) |

Behavior knobs (env vars):
-   READY_WAIT=0   # seconds to wait here for NODE+PORT; 0 = wait indefinitely (default)
-   PRINT_POLL=1   # polling interval (seconds) while waiting; default 1
-   BASTION=       # optional ProxyJump host, e.g. bastion.illinois.edu (adds -J to OUTER ssh)

## Notes:
- The session should be persistent for 