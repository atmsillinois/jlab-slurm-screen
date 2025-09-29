![keeling-jlab logo](https://raw.githubusercontent.com/atmsillinois/keeling-jlab/refs/heads/main/keeling-jlab.png)

# keeling-jlab

This script should be installed on keeling. It will start a jupyter lab session on a keeling compute node given inputted parameters, and then provide you a command to run in a separate terminal on your local machine to establish an ssh tunnel to a keeling compute node.  It waits to print SSH commands + Jupyter URL until the compute node has the jupyter lab session ready.

## Quickstart

### Install
```
git clone https://github.com/atmsillinois/jlab-slurm-screen
cd jlab-slurm-screen
chmod u+x jlab-slurm-screen.sh
```
You may wish to consider adding this folder to your path.

### Running
```
cd /path/to/jlab-slurm-screen/
./jlab-slurm-screen.sh hours=2 session=jlab cpus=4 mem=32G jlab_port=5678
```

### Quitting Early

If your session is called `jlab` (the default):
```
screen -S jlab -X quit
```

### Arguments (any order)

|Argument|Description|
| :--- | :--- |
| `hours=2`   |   time of job in hours |
| `session=jlab` |  prefix of slurm job  |
| `cpus=4`     |   number of cores     |
| `mem=32G`     |   memory per node (e.g. 32 gigabytes)  |
| `partition=seseml`   |   slurm partition  |
| `jlab_port=8888`     |   jupyerlab port to try (may change if not available)   |
| `dask_port=8787`     |   [optional] second port to tunnel (i.e., for dask dashboard) |

Behavior knobs (env vars)
-   `READY_WAIT=0`   # seconds to wait here for NODE+PORT; 0 = wait indefinitely (default)
-   `PRINT_POLL=1`   # polling interval (seconds) while waiting; default 1
-   `BASTION=1`       # optional ProxyJump host, e.g. bastion.illinois.edu (adds -J to OUTER ssh)

## Notes
- The session should be persistent for the alotted time.  Thus, to reconnect if you lose your connection to keeling during the alotted time, simply re-establish the ssh tunnel.
- Debugging info is available in `~/.jlab/<session>_<stamp>.{log,url,port,node,where,tunnel}` on keeling.
