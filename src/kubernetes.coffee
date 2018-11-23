# Description:
#   Hubot Kubernetes REST API helper commands.
#
#   Examples:
#   - `hubot k8s describe deploy hello-world namespace=default cluster=dev`
#   - `hubot k8s get po namespace=default cluster=dev app=hello-world`
#   - `hubot k8s delete po namespace=default cluster=dev hello-world-1234567890-xxxxx`
#   - `hubot k8s delete po namespace=default cluster=dev app=hello-world`
#   - `hubot k8s restart po namespace=default cluster=dev hello-world-1234567890-xxxxx`
#   - `hubot k8s restart po namespace=default cluster=dev app=hello-world`
#   - `hubot k8s logs hello-world-1234567890-xxxxx namespace=default cluster=dev 10`
#   - `hubot k8s logs previous hello-world-1234567890-xxxxx namespace=default cluster=dev 10`
#   - `hubot k8s logs hello-world-1234567890-xxxxx namespace=default cluster=dev container=hello-world 10`
#
# Configuration:
#   HUBOT_K8S_AUTHORIZED_ROLES
#
# Dependencies:
#   None
#
# Commands:
#   hubot k8s describe [deploy|po|rs|svc] <resource name> namespace=<namespace name> cluster=<cluster name> - Show details of a specific resource or group of resources under given cluster
#   hubot k8s get [deploy|po|rs|svc] namespace=<namespace name> cluster=<cluster name> [labels] - Display one or many resources under given cluster
#   hubot k8s [delete|restart] [po|pod|pods] namespace=<namespace name> cluster=<cluster name> [pod name|labels] - Delete pod by name, or by label selector
#   hubot k8s [log|logs] [previous] <pod name> namespace=<namespace name> cluster=<cluster name> [container=<container name>] [lines] - Print the logs for a container in a pod under given cluster
#
# Author:
#   - Can Yucel
#   - Kevin Li


async = require('async')
fs = require('fs')
path = require('path')
request = require 'request'
# request.debug = true


configPath = path.join __dirname, '..', 'conf'
clustersFile = path.join configPath, 'clusters.json'
clusters = JSON.parse(fs.readFileSync(clustersFile).toString('ascii'))

apisFile = path.join configPath, 'apis.json'
apis = JSON.parse(fs.readFileSync(apisFile).toString('ascii'))

if process.env.HUBOT_K8S_AUTHORIZED_ROLES
  authorizedRoles = process.env.HUBOT_K8S_AUTHORIZED_ROLES.split(',')
else
  authorizedRoles = ['admin', 'kube_admin']

isAuthorized = (robot, user, roles) ->
  if robot.auth.hasRole(user, roles)
    return true
  else
    return false

module.exports = (robot) ->

  aliasMap =
    'deploy': 'deployments'
    'deployment': 'deployments'
    'po': 'pods'
    'pod': 'pods'
    'rs': 'replicasets'
    'replicaset': 'replicasets'
    'svc': 'services'
    'service': 'services'

  decorateItemsFnMap =
    'deployments': (response) ->
      reply = ''
      for deploy in response.items
        {metadata: {name, creationTimestamp}, spec: {template: {spec: {containers}}}, status: {availableReplicas, readyReplicas, replicas, updatedReplicas}} = deploy

        reply = """
        #{reply}

        >*#{name}*:
        >Replicas: #{replicas} replicas | #{updatedReplicas} updatedReplicas | #{readyReplicas} readyReplicas | #{availableReplicas} availableReplicas
        >Age: #{timeSince(creationTimestamp)}
        """

        for container in containers
          {name, image} = container
          reply = "#{reply}\n>*Container: #{container.name}*: Image: #{container.image}"

      return reply

    'pods': (response) ->
      reply = ''
      for pod in response.items
        {metadata: {name}, status: {phase, startTime, containerStatuses}} = pod
        reply += ">*#{name}*: \n>Status: #{phase} for: #{timeSince(startTime)} \n"
        totalPod = 0
        readyPod = 0
        for cs in containerStatuses
          totalPod++
          {name, ready, restartCount, image} = cs
          readyPod += 1 if ready
          reply += ">Name: #{name} \n>Restarts: #{restartCount}\n>Image: #{image}\n"
        reply += ">Ready: #{readyPod}/#{totalPod}\n"
      return reply

    'replicasets': (response) ->
      reply = ''
      for rs in response.items
        image = rs.spec.template.spec.containers[0].image
        {metadata: {name, creationTimestamp}, spec: {template: {spec: {containers}}}, status: {replicas}} = rs

        reply = """
        #{reply}

        >*#{name}*:
        >>Replicas: #{replicas}\n>Age: #{timeSince(creationTimestamp)}
        """

        for container in containers
          {name, image} = container
          reply = "#{reply}\n>*Container: #{name}*: Image: #{image}"

      return reply

    'services': (response) ->
      reply = ''
      for service in response.items
        {metadata: {creationTimestamp}, spec: {clusterIP, ports}} = service
        ps = ""
        for p in ports
          {protocol, port} = p
          ps += "#{port}/#{protocol} "
        reply += ">*#{service.metadata.name}*:\n" +
        ">Cluster ip: #{clusterIP}\n>Ports: #{ps}\n>Age: #{timeSince(creationTimestamp)}\n"
      return reply

  decorateItemFnMap =
    'deployments': (response) ->
      {metadata: {name, creationTimestamp, labels}, spec: {template: {spec: {containers}}}, status: {availableReplicas, readyReplicas, replicas, updatedReplicas}} = response
      labels = (">        #{key}: #{value}" for key, value of labels)

      reply = """
      >*#{name}*:
      >Replicas: #{replicas} replicas | #{updatedReplicas} updatedReplicas | #{readyReplicas} readyReplicas | #{availableReplicas} availableReplicas
      >Age: #{timeSince(creationTimestamp)}
      >Labels:
      #{labels.join("\n")}
      """

      for container in containers
        {name, image, env} = container
        reply = "#{reply}\n>*Container: #{name}*: Image: #{image}\n>*Environment:*"
        for item in env
          reply = "#{reply}\n>#{item.name}:"
          if 'value' of item
            reply = "#{reply} #{item.value}"
          else if 'valueFrom' of item
            if 'secretKeyRef' of item.valueFrom
              reply = "#{reply} <set to the key '#{item.valueFrom.secretKeyRef.key}' in secret '#{item.valueFrom.secretKeyRef.name}'>"
            if 'configMapKeyRef' of item.valueFrom
              reply = "#{reply} <set to the key '#{item.valueFrom.configMapKeyRef.key}' of config map '#{item.valueFrom.configMapKeyRef.name}'>"

      return reply

    'pods': (response) ->
      reply = ''
      {metadata: {name, labels}, spec: {containers}, status: {phase, startTime, containerStatuses}} = response
      labels = (">        #{labelKey}: #{labelValue}" for labelKey, labelValue of labels)
      reply += ">*#{name}*: \n>Status: #{phase} for: #{timeSince(startTime)}\n>*Labels*: \n#{labels.join("\n")}\n"
      for cs in containerStatuses
        lastState = {}
        {image, lastState, name, ready, restartCount} = cs
        reply += ">Name: #{name} \n>Ready: #{ready}\n>Restarts: #{restartCount}\n>Image: #{image}"
        if Object.keys(lastState).length != 0
          for lastStateKev, lastStateValue of lastState
            {exitCode, finishedAt, reason, startedAt} = lastStateValue
            break
          reply = """
          #{reply}
          >*Last State*: #{lastStateKev}
          >        Reason: #{reason}
          >        Exit Code: #{exitCode}
          >        Started: #{startedAt}
          >        Finished: #{finishedAt}
          """

      for container in containers
        {name, env} = container
        reply = "#{reply}\n>*Container: #{name}*\n>*Environment:*"
        if env
          for item in env
            reply = "#{reply}\n>#{item.name}:"
            if 'value' of item
              reply = "#{reply} #{item.value}"
            else if 'valueFrom' of item
              if 'secretKeyRef' of item.valueFrom
                reply = "#{reply} <set to the key '#{item.valueFrom.secretKeyRef.key}' in secret '#{item.valueFrom.secretKeyRef.name}'>"
              if 'configMapKeyRef' of item.valueFrom
                reply = "#{reply} <set to the key '#{item.valueFrom.configMapKeyRef.key}' of config map '#{item.valueFrom.configMapKeyRef.name}'>"

      return reply

    'replicasets': (response) ->
      {metadata: {creationTimestamp, labels, name}, spec: {template: {spec: {containers}}}, status: {replicas}} = response
      image = containers[0].image
      labels = (">        #{key}: #{value}" for key, value of labels)

      reply = """
      >*#{name}*:
      >>Replicas: #{replicas}\n>Age: #{timeSince(creationTimestamp)}
      #{labels.join("\n")}
      """

      for container in containers
        {name, image, env} = container
        reply = "#{reply}\n>*Container: #{name}*: Image: #{image}\n>*Environment:*"
        for item in env
          reply = "#{reply}\n>#{item.name}:"
          if 'value' of item
            reply = "#{reply} #{item.value}"
          else if 'valueFrom' of item
            if 'secretKeyRef' of item.valueFrom
              reply = "#{reply} <set to the key '#{item.valueFrom.secretKeyRef.key}' in secret '#{item.valueFrom.secretKeyRef.name}'>"
            if 'configMapKeyRef' of item.valueFrom
              reply = "#{reply} <set to the key '#{item.valueFrom.configMapKeyRef.key}' of config map '#{item.valueFrom.configMapKeyRef.name}'>"

      return reply

    'services': (response) ->
      {metadata: {creationTimestamp, labels, name}, spec: {clusterIP, ports}} = response
      labels = (">         #{key}: #{value}" for key, value of labels)
      ps = ''
      for p in ports
        {protocol, port} = p
        ps += "#{port}/#{protocol}"

      reply = """
      >*#{name}*:
      >Cluster ip: #{clusterIP}
      >Ports: #{ps}
      >Age: #{timeSince(creationTimestamp)}
      >Labels:
      #{labels.join("\n")}
      """

      return reply

  decorateEvents = (resource, events) ->
    reply = '\n>*Event*:'
    {kind, metadata: {name}} = resource
    sourceKind = kind
    sourceName = name

    for item in events.items
      {type, reason, lastTimestamp, message, involvedObject: {kind, name}} = item
      if sourceKind == kind and sourceName == name
        reply = "#{reply}\n>Type: #{type}, Reason: #{reason}, Age: #{timeSince(lastTimestamp)}\n>Message: #{message}"

    return reply

  # hubot k8s get [deploy|po|rs|svc] namespace=<namespace name> cluster=<cluster name> [labels] - Display one or many resources under given cluster
  robot.respond /k8s\s+get\s+(deployments|pods|replicasets|services|deploy|po|rs|svc)\s+namespace=(\S+)\s+cluster=(\S+)\s*(.+)?/i, (res) ->
    console.log "User: #{res.message.user.name}, Command: #{res.message.text}"

    type = res.match[1]
    namespace = res.match[2]
    clusterName = res.match[3]
    labels = res.match[4] or ''

    for cluster in clusters
      if clusterName == cluster.name
        found = true
        break
    if not found
      return res.send "Could not find #{clusterName} cluster"

    if alias = aliasMap[type] then type = alias
    apiPath = apis[type]

    if 'apis' of cluster
      if type of cluster.apis
        apiPath = cluster.apis[type]

    if labels and labels != ''
      url = "#{apiPath}/namespaces/#{namespace}/#{type}?labelSelector=#{labels.trim()}"
    else
      url = "#{apiPath}/namespaces/#{namespace}/#{type}"

    kubeapi = new Request host: cluster.server, ca: cluster.ca, token: cluster.token
    kubeapi.get url, (err, response) ->
      if err
        robot.logger.error err
        return res.send "Could not fetch #{type} on *#{namespace}*"

      return res.send('Requested resource is not found') unless response.items and response.items.length

      reply = "\n"
      decorateItemsFn = decorateItemsFnMap[type] or ->
      reply = "Here is the list of #{type} running on *#{namespace}* namespace\n"
      reply += decorateItemsFn response

      res.send(reply)

  # hubot k8s describe [deploy|po|rs|svc] <resource name> namespace=<namespace name> cluster=<cluster name> - Show details of a specific resource or group of resources under given cluster
  robot.respond /k8s\s+describe\s+(deployment|pod|replicaset|service|deploy|po|rs|svc)\s+(\S+)\s+namespace=(\S+)\s+cluster=(\S+)/i, (res) ->
    console.log "User: #{res.message.user.name}, Command: #{res.message.text}"

    type = res.match[1]
    name = res.match[2]
    namespace = res.match[3]
    clusterName = res.match[4]

    for cluster in clusters
      if clusterName == cluster.name
        found = true
        break
    if not found
      return res.send "Could not find #{clusterName} cluster"

    if alias = aliasMap[type] then type = alias

    apiPath = apis[type]
    if 'apis' of cluster
      if type of cluster.apis
        apiPath = cluster.apis[type]
    url = "#{apiPath}/namespaces/#{namespace}/#{type}/#{name}"

    kubeapi = new Request host: cluster.server, ca: cluster.ca, token: cluster.token

    async.waterfall([
      describe = (callback) ->
        kubeapi.get url, (err, response) ->
          if err
            robot.logger.error err
            return callback(err, "Could not fetch #{type} on *#{namespace}*")

          if not response or 'metadata' not of response
            return callback('Requested resource is not found', 'Requested resource is not found')

          reply = "\n"
          decorateItemFn = decorateItemFnMap[type] or ->
          reply = "Here is the list of #{type} running on *#{namespace}* namespace\n"
          reply += decorateItemFn response;
          callback(null, reply, response);
      ,
      getEvents = (reply, response, callback) ->
        url = "api/v1/namespaces/#{namespace}/events"
        kubeapi.get url, (err, eventsResponse) ->
          if err
            robot.logger.error err
            return callback(null, "Could not fetch #{type} on *#{namespace}*")

          reply += decorateEvents response, eventsResponse

          callback(null, reply);
      ],
      replyResult = (error, reply) ->
        res.send(reply)
      );

  # hubot k8s [log|logs] [previous] <pod name> namespace=<namespace name> cluster=<cluster name> [container=<container name>] [lines] - Print the logs for a container in a pod under given cluster
  robot.respond /k8s\s+log(?:s)?\s+(previous)?\s*(\S+)\s+namespace=(\S+)\s+cluster=(\S+)\s*(?:container=(\S+))?\s*(\d+)?$/i, (res) ->
    console.log "User: #{res.message.user.name}, Command: #{res.message.text}"

    previous = res.match[1] or ''
    pod = res.match[2]
    namespace = res.match[3]
    clusterName = res.match[4]
    containerName = res.match[5]
    lines = res.match[6] or 10

    for cluster in clusters
      if clusterName == cluster.name
        found = true
        break
    if not found
      return res.send "Could not find #{clusterName} cluster"

    url = "api/v1/namespaces/#{namespace}/pods/#{pod}/log?tailLines=#{lines}"

    if previous and previous != ''
      url = "#{url}&previous=true"

    if containerName
      url = "#{url}&container=#{containerName}"

    kubeapi = new Request host: cluster.server, ca: cluster.ca, token: cluster.token
    kubeapi.get url, (err, response) ->
      if err
        robot.logger.error err
        return res.send "Could not fetch logs for #{pod} on *#{namespace}*"

      return res.send('Requested resource is not found') unless response

      reply = """
      Here are latest logs from pod *#{pod}* running on *#{namespace}*
      #{response}
      """

      res.send(reply)

  # hubot k8s [delete|restart] [po|pod|pods] namespace=<namespace name> cluster=<cluster name> [pod name|labels] - Delete pod by name, or by label selector
  robot.respond /k8s\s+(?:delete|restart)\s+po(?:d|ds)?\s+namespace=(\S+)\s+cluster=(\S+)\s+(\S+)/i, (res) ->
    console.log "User: #{res.message.user.name}, Command: #{res.message.text}"

    namespace = res.match[1]
    clusterName = res.match[2]
    target = res.match[3] or ''

    requiredRoles = authorizedRoles.concat ["kube_#{namespace}_admin"]

    if not isAuthorized(robot, robot.brain.userForName(res.message.user.name), requiredRoles)
      res.send("I can't do that, you need at least one of these roles: #{requiredRoles.join(',')}")
      return

    for cluster in clusters
      if clusterName == cluster.name
        found = true
        break
    if not found
      return res.send("Could not find #{clusterName} cluster")

    if target.indexOf('=') != -1
      url = "#{apis.pods}/namespaces/#{namespace}/pods?labelSelector=#{target.trim()}"
    else
      url = "#{apis.pods}/namespaces/#{namespace}/pods/#{target.trim()}"

    kubeapi = new Request host: cluster.server, ca: cluster.ca, token: cluster.token
    kubeapi.delete url, (err, response, data) ->
      if err
        robot.logger.error err
        return res.send "Could not delete #{target} on *#{namespace}*"

      if data.items
        if data.items.length
          msg = ("pod #{pod.metadata.name} deleted" for pod in data.items)
          res.send("#{msg.join('\n')}")
        else
          res.send('No resources found')
      else
        if response.statusCode != 200
          res.send("Error from server (NotFound): pods #{target} not found")
        else
          res.send("pod #{target} deleted")


class Request
  constructor: (options) ->
    {@host, @ca, @token} = options

  get: (path, callback) ->
    url = "#{@host}/#{path}"

    requestOptions =
      url: url
      timeout: 15000

    if @ca and @ca != ""
      requestOptions.ca = Buffer(@ca, 'base64').toString('ascii')

    if @token and @token != ''
      requestOptions.headers =
        Authorization: "Bearer #{Buffer(@token, 'base64').toString('ascii')}"

    console.log "Request url: #{url}"
    # console.log requestOptions

    request.get requestOptions, (err, response, data) ->

      return callback(err) if err

      if response.statusCode != 200
        return callback new Error("Status code is not OK: #{response.statusCode}")

      # console.log data

      if data.startsWith "{"
        callback null, JSON.parse(data)
      else
        callback null, data

  delete: (path, callback) ->
    url = "#{@host}/#{path}"

    requestOptions =
      url: url
      timeout: 15000

    if @ca and @ca != ""
      requestOptions.ca = Buffer(@ca, 'base64').toString('ascii')

    if @token and @token != ''
      requestOptions.headers =
        Authorization: "Bearer #{Buffer(@token, 'base64').toString('ascii')}"

    console.log "Request url: #{url}"
    # console.log requestOptions

    request.delete requestOptions, (err, response, data) ->

      if err
        callback err
      else
        callback null, response, JSON.parse(data)


timeSince = (date) ->
  d = new Date(date).getTime()
  seconds = Math.floor((new Date() - d) / 1000)

  return "#{Math.floor(seconds)}s"  if seconds < 60

  return "#{Math.floor(seconds/60)}m"  if seconds < 3600

  return "#{Math.floor(seconds/3600)}h"  if seconds < 86400

  return "#{Math.floor(seconds/86400)}d"  if seconds < 2592000

  return "#{Math.floor(seconds/2592000)}mo"  if seconds < 31536000

  return "#{Math.floor(seconds/31536000)}y"
