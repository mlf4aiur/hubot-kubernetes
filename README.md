Kubernetes for Hubot
====================

Query your Kubernetes resources using Hubot.

Installation
------------

Add `hubot-kubernetes` to your `package.json` file:

    "dependencies": {
      "hubot": ">= 2.5.1",
      "hubot-scripts": ">= 2.4.2",
      "hubot-redis-brain": "0.0.3",
      "hubot-auth": "^1.2.0",
      "hubot-kubernetes": ">= 0.0.0"
    }

Then add "hubot-kubernetes" to your `external-scripts.json` file:

    ["hubot-kubernetes"]

Finally, run `npm install hubot-kubernetes` and you're done!

Configuration
-------------

- apis.json - Default api prefix
- clusters.json - Settings for cluster connectin, host, ca, token, etc

Usage
-----

 > `hubot k8s describe [deploy|po|rs|svc] <resource name> namespace=<namespace name> cluster=<cluster name>`

Show details of a specific resource or group of resources under given cluster.

 > `hubot k8s get [deploy|po|rs|svc] namespace=<namespace name> cluster=<cluster name> [labels]`

Display one or many resources under given cluster.

 > `hubot k8s [delete|restart] [po|pod|pods] namespace=<namespace name> cluster=<cluster name> [pod name|labels]`

Delete pod by name, or by label selector under given cluster. Note that this also
"restarts" a service.

 > `hubot k8s [log|logs] [previous] <pod name> namespace=<namespace name> cluster=<cluster name> [container=<container name>] [lines]`

Print the logs for a container in a pod under given cluster, default display only the most recent 10 lines of output.

Example
-------

> `hubot k8s describe deploy hello-world namespace=default cluster=dev`

> `hubot k8s get po namespace=default cluster=dev app=hello-world`

> `hubot k8s delete po namespace=default cluster=dev hello-world-1234567890-xxxxx`

> `hubot k8s delete po namespace=default cluster=dev app=hello-world`

> `hubot k8s restart po namespace=default cluster=dev hello-world-1234567890-xxxxx`

> `hubot k8s restart po namespace=default cluster=dev app=hello-world`

> `hubot k8s logs hello-world-3876734081-7b882 namespace=default cluster=dev 10`

> `hubot k8s logs previous hello-world-1234567890-xxxxx namespace=default cluster=dev 10`

> `hubot k8s logs hello-world-1234567890-xxxxx namespace=default cluster=dev container=hello-world 10`

License
-------

See the [LICENSE](LICENSE) file for license rights and limitations (MIT).
