###############################################################################
#
# SageMathCloud: A collaborative web-based interface to Sage, IPython, LaTeX and the Terminal.
#
#    Copyright (C) 2015, William Stein
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

EXPERIMENTAL = false

###

require('compute').compute_server(db_hosts:['db0'], cb:(e,s)->console.log(e);global.s=s)

s.project(project_id:'eb5c61ae-b37c-411f-9509-10adb51eb90b',cb:(e,p)->global.p=p;console.log(e))

###


# obviously don't want to trigger this too quickly, since it may mean file loss.
AUTOMATIC_FAILOVER_TIME_S = 60*5  # 5 minutes

SERVER_STATUS_TIMEOUT_S = 7  # 7 seconds

#################################################################
#
# compute-client -- a node.js client that connects to a TCP server
# that is used by the hubs to organize compute nodes
#
#################################################################

# IMPORTANT: see schema.coffee for some important information about the project states.
STATES = require('smc-util/schema').COMPUTE_STATES

net         = require('net')
fs          = require('fs')
{EventEmitter} = require('events')

async       = require('async')
winston     = require('winston')
program     = require('commander')


uuid        = require('node-uuid')

misc_node   = require('smc-util-node/misc_node')

message     = require('smc-util/message')
misc        = require('smc-util/misc')

{rethinkdb} = require('./rethink')


# Set the log level
winston.remove(winston.transports.Console)
winston.add(winston.transports.Console, {level: 'debug', timestamp:true, colorize:true})

{defaults, required} = misc

TIMEOUT = 60*60

BTRFS   = process.env.SMC_BTRFS ? '/projects'

BUCKET  = process.env.SMC_BUCKET
ARCHIVE = process.env.SMC_ARCHIVE

if process.env.SMC_STORAGE?
    STORAGE = process.env.SMC_STORAGE
else if misc.startswith(require('os').hostname(), 'compute')   # my official deploy: TODO -- should be moved to conf file.
    STORAGE = 'storage0-us'
else
    STORAGE = ''
    # TEMPORARY:


#################################################################
#
# Client code -- runs in hub
#
#################################################################

###
x={};require('compute').compute_server(keyspace:'devel',cb:(e,s)->console.log(e);x.s=s)
###
compute_server_cache = undefined
exports.compute_server = compute_server = (opts) ->
    opts = defaults opts,
        database : undefined
        db_name  : 'smc'
        db_hosts : ['localhost']
        cb       : required
    if compute_server_cache?
        opts.cb(undefined, compute_server_cache)
    else
        new ComputeServerClient(opts)

class ComputeServerClient
    constructor: (opts) ->
        opts = defaults opts,
            database : undefined
            db_name  : 'smc'
            db_hosts : ['localhost']
            cb       : required
        dbg = @dbg("constructor")
        @_project_cache = {}
        @_project_cache_cb = {}
        if opts.database?
            dbg("using database")
            @database = opts.database
            compute_server_cache = @
            opts.cb(undefined, @)
        else if opts.db_name?
            dbg("using database '#{opts.db_name}'")
            fs.readFile "#{process.cwd()}/data/secrets/rethinkdb", (err, password) =>
                if err
                    winston.debug("warning: no password file -- will only work if there is no password set.")
                    password = undefined
                else
                    password = password.toString().trim()
                @database = rethinkdb
                    hosts    : opts.db_hosts
                    database : opts.db_name
                    password : password
                    cb       : (err) =>
                       if err
                          opts.cb(err)
                       else
                          compute_server_cache = @
                          opts.cb(undefined, @)
        else
            opts.cb("database or keyspace must be specified")

    dbg: (method) =>
        return (m) => winston.debug("ComputeServerClient.#{method}: #{m}")

    ###
    # get info about server and add to database

        require('compute').compute_server(db_hosts:['localhost'],cb:(e,s)->console.log(e);s.add_server(host:'compute0-us', cb:(e)->console.log("done",e)))

        require('compute').compute_server(db_hosts:['smc0-us-central1-c'],cb:(e,s)->console.log(e);s.add_server(host:'compute0-us', cb:(e)->console.log("done",e)))

require('compute').compute_server(db_hosts:['smc0-us-central1-c'],cb:(e,s)->console.log(e);s.add_server(experimental:true, host:'compute0-amath-us', cb:(e)->console.log("done",e)))

         require('compute').compute_server(cb:(e,s)->console.log(e);s.add_server(host:os.hostname(), cb:(e)->console.log("done",e)))
    ###
    add_server: (opts) =>
        opts = defaults opts,
            host         : required
            dc           : ''        # deduced from hostname (everything after -) if not given
            experimental : false     # if true, don't allocate new projects here
            timeout      : 30
            cb           : required
        dbg = @dbg("add_server(#{opts.host})")
        dbg("adding compute server to the database by grabbing conf files, etc.")

        if not opts.host
            i = opts.host.indexOf('-')
            if i != -1
                opts.dc = opts.host.slice(0,i)

        get_file = (path, cb) =>
            dbg("get_file: #{path}")
            misc_node.execute_code
                command : "ssh"
                path    : process.cwd()
                timeout : opts.timeout
                args    : ['-o', 'StrictHostKeyChecking=no', opts.host, "cat #{path}"]
                verbose : 0
                cb      : (err, output) =>
                    if err
                        cb(err)
                    else if output?.stderr and output.stderr.indexOf('No such file or directory') != -1
                        cb(output.stderr)
                    else
                        cb(undefined, output.stdout)

        port = undefined; secret = undefined
        async.series([
            (cb) =>
                async.parallel([
                    (cb) =>
                        get_file program.port_file, (err, x) =>
                            port = parseInt(x); cb(err)
                    (cb) =>
                        get_file program.secret_file, (err, x) =>
                            secret = x; cb(err)
                ], cb)
            (cb) =>
                dbg("update database")
                @database.save_compute_server
                    host         : opts.host
                    dc           : opts.dc
                    port         : port
                    secret       : secret
                    experimental : opts.experimental
                    cb           : cb
        ], opts.cb)

    # Choose a host from the available compute_servers according to some
    # notion of load balancing (not really worked out yet)
    assign_host: (opts) =>
        opts = defaults opts,
            exclude  : []
            cb       : required
        dbg = @dbg("assign_host")
        dbg("querying database")
        @status
            cb : (err, nodes) =>
                if err
                    opts.cb(err)
                else
                    # Ignore any exclude nodes
                    for host in opts.exclude
                        delete nodes[host]
                    # We want to choose the best (="least loaded?") working node.
                    v = []
                    for host, info of nodes
                        if EXPERIMENTAL
                            # only use experimental nodes
                            if not info.experimental
                                continue
                        else
                            # definitely don't assign experimental nodes
                            if info.experimental
                                continue
                        v.push(info)
                        info.host = host
                        if info.error?
                            info.score = 0
                        else
                            # 10 points if no load; 0 points if massive load
                            info.score = Math.max(0, Math.round(10*(1 - info.load[0])))
                            # 1 point for each Gigabyte of available RAM that won't
                            # result in swapping if used
                            info.score += Math.round(info.memory.MemAvailable/1000)
                    if v.length == 0
                        opts.cb("no hosts available")
                        return
                    # sort so highest scoring is first.
                    v.sort (a,b) =>
                        if a.score < b.score
                            return 1
                        else if a.score > b.score
                            return -1
                        else
                            return 0
                    dbg("scored host info = #{misc.to_json(([info.host,info.score] for info in v))}")
                    # finally choose one of the hosts with the highest score at random.
                    best_score = v[0].score
                    i = 0
                    while i < v.length and v[i].score == best_score
                        i += 1
                    w = v.slice(0,i)
                    opts.cb(undefined, misc.random_choice(w).host)

    remove_from_cache: (opts) =>
        opts = defaults opts,
            host : required
        if @_socket_cache?
            delete @_socket_cache[opts.host]

    # get a socket connection to a particular compute server
    socket: (opts) =>
        opts = defaults opts,
            host : required
            cb   : required
        dbg = @dbg("socket(#{opts.host})")

        if not @_socket_cache?
            @_socket_cache = {}
        socket = @_socket_cache[opts.host]
        if socket?
            opts.cb(undefined, socket)
            return
        info = undefined
        async.series([
            (cb) =>
                dbg("getting port and secret...")
                @database.get_compute_server
                    host : opts.host
                    cb   : (err, x) =>
                        info = x; cb(err)
            (cb) =>
                dbg("connecting to #{opts.host}:#{info.port}...")
                misc_node.connect_to_locked_socket
                    host    : opts.host
                    port    : info.port
                    token   : info.secret
                    timeout : 15
                    cb      : (err, socket) =>
                        if err
                            dbg("failed to connect: #{err}")
                            cb(err)
                        else
                            @_socket_cache[opts.host] = socket
                            misc_node.enable_mesg(socket)
                            socket.id = uuid.v4()
                            dbg("successfully connected -- socket #{socket.id}")
                            socket.on 'close', () =>
                                dbg("socket #{socket.id} closed")
                                for _, p of @_project_cache
                                    # tell every project whose state was set via
                                    # this socket that the state is no longer known.
                                    if p._socket_id == socket.id
                                        p.clear_state()
                                        delete p._socket_id
                                if @_socket_cache[opts.host]?.id == socket.id
                                    delete @_socket_cache[opts.host]
                                socket.removeAllListeners()
                            socket.on 'mesg', (type, mesg) =>
                                if type == 'json'
                                    if mesg.event == 'project_state_update'
                                        winston.debug("state_update #{misc.to_safe_str(mesg)}")
                                        p = @_project_cache[mesg.project_id]
                                        if p? and p.host == opts.host  # ignore updates from wrong host
                                            p._state      = mesg.state
                                            p._state_time = new Date()
                                            p._state_set_by = socket.id
                                            p._state_error = mesg.state_error  # error switching to this state
                                            # error can't be undefined below, according to rethinkdb 2.1.1
                                            state = {state:p._state, time:p._state_time, error:p._state_error ? null}
                                            @database.table('projects').get(mesg.project_id).update(state:state).run (err) =>
                                                if err
                                                    winston.debug("Error setting state of #{mesg.project_id} in database -- #{err}")

                                            p.emit(p._state, p)
                                            if STATES[mesg.state].stable
                                                p.emit('stable', mesg.state)
                                    else
                                        winston.debug("mesg (hub <- #{opts.host}): #{misc.to_safe_str(mesg)}")
                            cb()
        ], (err) =>
            opts.cb(err, @_socket_cache[opts.host])
        )

    ###
    Send message to a server and get back result:

    x={};require('compute').compute_server(keyspace:'devel',cb:(e,s)->console.log(e);x.s=s;x.s.call(host:'localhost',mesg:{event:'ping'},cb:console.log))
    ###
    call: (opts) =>
        opts = defaults opts,
            host    : required
            mesg    : undefined
            timeout : 15
            project : undefined
            cb      : required

        dbg = @dbg("call(hub --> #{opts.host})")
        #dbg("(hub --> compute) #{misc.to_json(opts.mesg)}")
        #dbg("(hub --> compute) #{misc.to_safe_str(opts.mesg)}")
        socket = undefined
        resp = undefined
        if not opts.mesg.id?
            opts.mesg.id = uuid.v4()
        async.series([
            (cb) =>
                @socket
                    host : opts.host
                    cb   : (err, s) =>
                        socket = s; cb(err)
            (cb) =>
                if opts.project?
                    # record that this socket was used by the given project
                    # (so on close can invalidate info)
                    opts.project._socket_id = socket.id
                socket.write_mesg 'json', opts.mesg, (err) =>
                    if err
                        cb("error writing to socket -- #{err}")
                    else
                        dbg("waiting to receive response with id #{opts.mesg.id}")
                        socket.recv_mesg
                            type    : 'json'
                            id      : opts.mesg.id
                            timeout : opts.timeout
                            cb      : (mesg) =>
                                dbg("got response -- #{misc.to_safe_str(mesg)}")
                                if mesg.event == 'error'
                                    dbg("error = #{mesg.error}")
                                    cb(mesg.error)
                                else
                                    delete mesg.id
                                    resp = mesg
                                    dbg("success: resp=#{misc.to_safe_str(resp)}")
                                    cb()
        ], (err) =>
            opts.cb(err, resp)
        )

    ###
    Get a project:
        x={};require('compute').compute_server(keyspace:'devel',cb:(e,s)->console.log(e);x.s=s;x.s.project(project_id:'20257d4e-387c-4b94-a987-5d89a3149a00',cb:(e,p)->console.log(e);x.p=p))
    ###
    project: (opts) =>
        opts = defaults opts,
            project_id : required
            cb         : required
        p = @_project_cache[opts.project_id]
        if p?
            opts.cb(undefined, p)
        else
            # This v is so that if project is called again before the first
            # call returns, then both calls get the same project back.
            v = @_project_cache_cb[opts.project_id]
            if v?
                v.push(opts.cb)
                return
            v = @_project_cache_cb[opts.project_id] = [opts.cb]
            new ProjectClient
                project_id     : opts.project_id
                compute_server : @
                cb             : (err, project) =>
                    delete @_project_cache_cb[opts.project_id]
                    if not err
                        @_project_cache[opts.project_id] = project
                    for cb in v
                        if err
                            cb(err)
                        else
                            cb(undefined, project)

    # get status information about compute servers
    status: (opts) =>
        opts = defaults opts,
            hosts   : undefined   # list of hosts or undefined=all compute servers
            timeout : SERVER_STATUS_TIMEOUT_S           # compute server must respond this quickly or {error:some sort of timeout error..}
            cb      : required    # cb(err, {host1:status, host2:status2, ...})
        dbg = @dbg('status')
        result = {}
        async.series([
            (cb) =>
                if opts.hosts?
                    cb(); return
                dbg("getting list of all compute server hostnames from database")
                @database.get_all_compute_servers
                    cb : (err, s) =>
                        if err
                            cb(err)
                        else
                            for x in s
                                result[x.host] = {experimental:x.experimental}
                            dbg("got #{s.length} compute servers")
                            cb()
            (cb) =>
                dbg("querying servers for their status")
                f = (host, cb) =>
                    @call
                        host    : host
                        mesg    : message.compute_server_status()
                        timeout : opts.timeout
                        cb      : (err, resp) =>
                            if err
                                result[host].error = err
                            else
                                if not resp?.status
                                    result[host].error = "invalid response -- no status"
                                else
                                    for k, v of resp.status
                                        result[host][k] = v
                            cb()
                async.map(misc.keys(result), f, cb)
        ], (err) =>
            opts.cb(err, result)
        )

    # WARNING: vacate_compute_server is **UNTESTED**
    vacate_compute_server: (opts) =>
        opts = defaults opts,
            compute_server : required    # array
            move           : false
            targets        : undefined  # array
            cb             : required
        @database.get_projects_on_compute_server
            compute_server : opts.compute_server
            columns        : ['project_id']
            cb             : (err, results) =>
                if err
                    opts.cb(err)
                else
                    winston.debug("got them; now processing...")
                    v = (x.project_id for x in results)
                    winston.debug("found #{v.length} on #{opts.compute_server}")
                    i = 0
                    f = (project_id, cb) =>
                        winston.debug("moving #{project_id} off of #{opts.compute_server}")
                        if opts.move
                            @project
                                project_id : project_id
                                cb         : (err, project) =>
                                    if err
                                        cb(err)
                                    else
                                        if opts.targets?
                                            i = (i + 1)%opts.targets.length
                                        project.move
                                            target : opts.targets?[i]
                                            cb     : cb
                    async.mapLimit(v, 15, f, opts.cb)

    ###
    projects = require('misc').split(fs.readFileSync('/home/salvus/work/2015-amath/projects').toString())
    require('compute').compute_server(db_hosts:['smc0-us-central1-c'],keyspace:'salvus',cb:(e,s)->console.log(e); s.set_quotas(projects:projects, cores:4, cb:(e)->console.log("DONE",e)))
    ###
    set_quotas: (opts) =>
        opts = defaults opts,
            projects     : required    # array of project id's
            disk_quota   : undefined
            cores        : undefined
            memory       : undefined
            cpu_shares   : undefined
            network      : undefined
            mintime      : undefined  # in seconds
            cb           : required
        projects = opts.projects
        delete opts.projects
        cb = opts.cb
        delete opts.cb
        f = (project_id, cb) =>
            o = misc.copy(opts)
            o.cb = cb
            @project
                project_id : project_id
                cb         : (err, project) =>
                    project.set_quotas(o)
        async.mapLimit(projects, 10, f, cb)

    ###
    projects = require('misc').split(fs.readFileSync('/home/salvus/tmp/projects').toString())
    require('compute').compute_server(db_hosts:['db0'], cb:(e,s)->console.log(e); s.move(projects:projects, target:'compute5-us', cb:(e)->console.log("DONE",e)))

    s.move(projects:projects, target:'compute4-us', cb:(e)->console.log("DONE",e))
    ###
    move: (opts) =>
        opts = defaults opts,
            projects : required    # array of project id's
            target   : required
            limit    : 10
            cb       : required
        projects = opts.projects
        delete opts.projects
        cb = opts.cb
        delete opts.cb
        f = (project_id, cb) =>
            @project
                project_id : project_id
                cb         : (err, project) =>
                    project.move(target: opts.target, cb:cb)
        async.mapLimit(projects, opts.limit, f, cb)

    # x={};require('compute').compute_server(db_hosts:['smc0-us-central1-c'], cb:(e,s)->console.log(e);x.s=s;x.s.tar_backup_recent(max_age_h:1, cb:(e)->console.log("DONE",e)))
    tar_backup_recent: (opts) =>
        opts = defaults opts,
            max_age_h : required
            limit     : 1            # number to backup in parallel
            gap_s     : 5            # wait this long between backing up each project
            cb        : required
        dbg = @dbg("tar_backup_recent")
        target = undefined
        async.series([
            (cb) =>
                @database.recently_modified_projects
                    max_age_s : opts.max_age_h*60*60
                    cb        : (err, results) =>
                        if err
                            cb(err)
                        else
                            dbg("got #{results.length} projects modified in the last #{opts.max_age_h} hours")
                            target = results
                            cb()

            (cb) =>
                i = 0
                n = misc.len(target)
                winston.debug("next backing up resulting #{n} targets")
                running = {}
                f = (project_id, cb) =>
                  fs.exists "/projects/#{project_id}", (exists) =>
                    if not exists
                       winston.debug("skipping #{project_id} since not here")
                       cb(); return
                    j = i + 1
                    i += 1
                    running[j] = project_id
                    winston.debug("*****************************************************")
                    winston.debug("** #{j}/#{n}: #{project_id}")
                    winston.debug("RUNNING=#{misc.to_json(misc.keys(running))}")
                    winston.debug("*****************************************************")

                    smc_compute
                        args : ['tar_backup', project_id]
                        cb   : (err) =>
                            delete running[j]
                            winston.debug("*****************************************************")
                            winston.debug("** #{j}/#{n}: DONE -- #{project_id}, DONE")
                            winston.debug("RUNNING=#{misc.to_json(running)}")
                            winston.debug("*****************************************************")
                            winston.debug("result of backing up #{project_id}: #{err}")
                            if err
                                cb(err)
                            else
                                winston.debug("Now waiting #{opts.gap_s} seconds...")
                                setTimeout(cb, opts.gap_s*1000)
                async.mapLimit(target, opts.limit, f, cb)
        ], opts.cb)

    # Query database for all projects that are opened (so deployed on a compute VM), but
    # have not been touched in at least the given number of days.  For each such project,
    # stop it, save it, and close it (deleting files off compute server).  This should be
    # run periodically as a maintenance operation to free up disk space on compute servers.
    #   require('compute').compute_server(db_hosts:['db0'], cb:(e,s)->console.log(e);global.s=s)
    #   s.close_open_unused_projects(dry_run:true, min_age_days:60, max_age_days:180, limit:1, host:'compute2-us', cb:(e,x)->console.log("DONE",e))
    close_open_unused_projects: (opts) =>
        opts = defaults opts,
            min_age_days : required
            max_age_days : required
            host         : required    # server on which to close unused projects
            limit        : 1           # number to close in parallel
            dry_run      : false       # if true, just explain what would get deleted, but don't actually do anything.
            cb           : required
        dbg = @dbg("close_unused_projects")
        target = undefined
        async.series([
            (cb) =>
                @database.get_open_unused_projects
                    min_age_days : opts.min_age_days
                    max_age_days : opts.max_age_days
                    host         : opts.host
                    cb           : (err, results) =>
                        if err
                            cb(err)
                        else
                            dbg("got #{results.length} open projects that were not used in the last #{opts.min_age_days} days")
                            target = results
                            cb()
            (cb) =>
                n = misc.len(target)
                winston.debug("There are #{n} projects to save and close.")
                if opts.dry_run
                    cb()
                    return
                i = 0
                done = 0
                winston.debug("next saving and closing #{n} projects")
                running = {}
                f = (project_id, cb) =>
                    j = i + 1
                    i += 1
                    running[j] = project_id
                    winston.debug("*****************************************************")
                    winston.debug("** #{j}/#{n}: #{project_id}")
                    winston.debug("RUNNING=#{misc.to_json(misc.keys(running))}")
                    winston.debug("*****************************************************")
                    @project
                        project_id : project_id
                        cb         : (err, project) =>
                            if err
                                winston.debug("ERROR!!! #{err}")
                                cb(err)
                            else
                                state = undefined
                                async.series([
                                    (cb) =>
                                        # see if project is really not closed
                                        project.state
                                            cb : (err, s) =>
                                                state = s?.state; cb(err)
                                    (cb) =>
                                        if state == 'closed'
                                            cb(); return
                                        # this causes the process of closing to start; but cb is called before it is done
                                        project.close
                                            force  : false
                                            nosave : false
                                            cb     : cb
                                    (cb) =>
                                        if state == 'closed'
                                            cb(); return
                                        # wait until closed
                                        project.once 'closed', => cb()
                                ], (err) =>
                                    delete running[j]
                                    done += 1
                                    winston.debug("*****************************************************")
                                    winston.debug("FINISHED #{done} of #{n}")
                                    winston.debug("** #{j}/#{n}: DONE -- #{project_id}, DONE")
                                    winston.debug("RUNNING=#{misc.to_json(running)}")
                                    winston.debug("*****************************************************")
                                    winston.debug("result of closing #{project_id}: #{err}")
                                    cb(err)
                                )
                async.mapLimit(target, opts.limit, f, cb)
        ], opts.cb)



class ProjectClient extends EventEmitter
    constructor: (opts) ->
        opts = defaults opts,
            project_id     : required
            compute_server : required
            cb             : required
        @project_id = opts.project_id
        @compute_server = opts.compute_server
        @clear_state()
        dbg = @dbg('constructor')
        dbg("getting project's host")
        @update_host
            cb : (err) =>
                if err
                    dbg("failed to create project getting host -- #{err}")
                    opts.cb(err)
                else
                    dbg("successfully created project on '#{@host}'")
                    opts.cb(undefined, @)

        # Watch for state change to saving, which means that a save
        # has started (possibly initiated by another hub).  We note
        # that in the @_last_save variable so we don't even try
        # to save until later.
        @on 'saving', () =>
            @_last_save = new Date()

    dbg: (method) =>
        (m) => winston.debug("ProjectClient(project_id='#{@project_id}','#{@host}').#{method}: #{m}")

    _set_host: (host) =>
        old_host = @host
        @host = host
        if old_host? and host != old_host
            @dbg("host_changed from #{old_host} to #{host}")
            @emit('host_changed', @host)  # event whenever host changes from one set value to another (e.g., move or failover)

    clear_state: () =>
        @dbg("clear_state")()
        delete @_state
        delete @_state_time
        delete @_state_error
        delete @_state_set_by
        if @_state_cache_timeout?
             clearTimeout(@_state_cache_timeout)
             delete @_state_cache_timeout

    update_host: (opts) =>
        opts = defaults opts,
            cb : undefined
        host          = undefined
        assigned      = undefined
        previous_host = @host
        dbg = @dbg("update_host")
        t = misc.mswalltime()
        async.series([
            (cb) =>
                dbg("querying database for compute server")
                @compute_server.database.get_project_host
                    project_id : @project_id
                    cb         : (err, x) =>
                        if err
                            dbg("error querying database -- #{err}")
                            cb(err)
                        else
                            if x
                                {host, assigned} = x
                            if host   # important: DO NOT just do "host?", since host='' is in the database for older projects!
                                dbg("got host='#{host}' that was assigned #{assigned}")
                            else
                                dbg("no host assigned")
                            cb()
            (cb) =>
                if host
                    # The host might no longer be defined at all, so we should check this here.
                    dbg("make sure the host still exists")
                    @compute_server.database.get_compute_server
                        host : host
                        cb   : (err, x) =>
                            if err
                                cb(err)
                            else
                                if not x
                                    # The compute server doesn't exist anymore.  Forget our useless host
                                    # assignment and get a new host below.
                                    host = undefined
                                cb()
                else
                    cb()


            (cb) =>
                if host
                    cb()
                else
                    dbg("assigning some host")
                    @compute_server.assign_host
                        cb : (err, h) =>
                            if err
                                dbg("error assigning random host -- #{err}")
                                cb(err)
                            else
                                host = h
                                dbg("new host = #{host}")
                                @compute_server.database.set_project_host
                                    project_id : @project_id
                                    host       : host
                                    cb         : (err, x) =>
                                        assigned = x; cb(err)
        ], (err) =>
            if not err
                @_set_host(host)
                @assigned = assigned  # when host was assigned
                dbg("henceforth using host='#{@host}' that was assigned #{@assigned}")
                if host != previous_host
                    @clear_state()
                    dbg("HOST CHANGE: '#{previous_host}' --> '#{host}'")
            dbg("time=#{misc.mswalltime(t)}ms")
            opts.cb?(err, host)
        )

    _action: (opts) =>
        opts = defaults opts,
            action  : required
            args    : undefined
            timeout : 30
            cb      : required
        dbg = @dbg("_action(action=#{opts.action})")
        dbg("args=#{misc.to_safe_str(opts.args)}")
        dbg("first update host to use the right compute server")
        @update_host
            cb : (err) =>
                if err
                    dbg("error updating host #{err}")
                    opts.cb(err); return
                dbg("calling compute server at '#{@host}'")
                @compute_server.call
                    host    : @host
                    project : @
                    mesg    :
                        message.compute
                            project_id : @project_id
                            action     : opts.action
                            args       : opts.args
                    timeout : opts.timeout
                    cb      : (err, resp) =>
                        if err
                            dbg("error calling compute server -- #{err}")
                            @compute_server.remove_from_cache(host:@host)
                            opts.cb(err)
                        else
                            dbg("got response #{misc.to_safe_str(resp)}")
                            if resp.error?
                                opts.cb(resp.error)
                            else
                                opts.cb(undefined, resp)

    ###
    x={};require('compute').compute_server(cb:(e,s)->console.log(e);x.s=s;x.s.project(project_id:'20257d4e-387c-4b94-a987-5d89a3149a00',cb:(e,p)->console.log(e);x.p=p; x.p.state(cb:console.log)))
    ###

    # STATE/STATUS info
    state: (opts) =>
        opts = defaults opts,
            force  : true    # don't use local cached or value obtained
            update : false   # make server recompute state (forces switch to stable state)
            cb     : required
        dbg = @dbg("state(force:#{opts.force},update:#{opts.update})")

        if @_state_time? and @_state?
            timeout = STATES[@_state].timeout * 1000
            if timeout?
                time_in_state = new Date() - @_state_time
                if time_in_state > timeout
                    dbg("forcing update since time_in_state=#{time_in_state}ms exceeds timeout=#{timeout}ms")
                    opts.update = true
                    opts.force  = true

        if opts.force or opts.update or (not @_state? or not @_state_time?)
            dbg("calling remote server for state")
            @_action
                action : "state"
                args   : if opts.update then ['--update']
                cb     : (err, resp) =>
                    if err
                        dbg("problem getting state -- #{err}")
                        opts.cb(err)
                    else
                        dbg("got state='#{@_state}'")
                        @clear_state()
                        @_state       = resp.state
                        @_state_time  = resp.time
                        @_state_error = resp.state_error

                        # Set the latest info about state that we got in the database so that
                        # clients and other hubs no about it.
                        state = {state:@_state, time:@_state_time, error:@_state_error ? null}
                        @compute_server.database.table('projects').get(@project_id).update(state:state).run (err) =>
                            if err
                                dbg("Error setting state of #{@project_id} in database -- #{err}")

                        f = () =>
                            dbg("clearing cache due to timeout")
                            @clear_state()
                        @_state_cache_timeout = setTimeout(f, 30000)
                        opts.cb(undefined, resp)
        else
            dbg("getting state='#{@_state}' from cache")
            x =
                state : @_state
                time  : @_state_time
                error : @_state_error
            opts.cb(undefined, x)

    # information about project (ports, state, etc. )
    status: (opts) =>
        opts = defaults opts,
            cb     : required
        dbg = @dbg("status")
        dbg()
        status = undefined
        async.series([
            (cb) =>
                @_action
                    action : "status"
                    cb     : (err, s) =>
                        if not err
                            status = s
                        cb(err)
            (cb) =>
                dbg("get status from compute server")
                f = (cb) =>
                    @_action
                        action : "status"
                        cb     : (err, s) =>
                            if not err
                                status = s
                                # save status in database
                                @compute_server.database.table('projects').get(@project_id).update(status:status).run(cb)
                            else
                                cb(err)
                # we retry getting status with exponential backoff until we hit max_time, which
                # triggers failover of project to another node.
                misc.retry_until_success
                    f           : f
                    start_delay : 15000
                    max_time    : AUTOMATIC_FAILOVER_TIME_S*1000
                    cb          : (err) =>
                        if err
                            m = "failed to get status -- project not working on #{@host} -- initiating automatic move to a new node -- #{err}"
                            dbg(m)
                            cb(m)
                            # Now we actually initiate the failover, which could take a long time,
                            # depending on how big the project is.
                            @move
                                force : true
                                cb    : (err) =>
                                    dbg("result of failover -- #{err}")
                        else
                            cb()
            (cb) =>
                @get_quotas
                    cb : (err, quotas) =>
                        if err
                            cb(err)
                        else
                            status.host = @host
                            status.ssh = @host
                            status.quotas = quotas
                            cb()
        ], (err) =>
            if err
                opts.cb(err)
            else
                opts.cb(undefined, status)
        )


    # COMMANDS:

    # open project files on some node
    open: (opts) =>
        opts = defaults opts,
            ignore_recv_errors : false
            cb     : required
        @dbg("open")()
        args = [@assigned]
        if opts.ignore_recv_errors
            args.push('--ignore_recv_errors')
        @_action
            action : "open"
            args   : args
            cb     : opts.cb

    # start local_hub daemon running (must be opened somewhere)
    start: (opts) =>
        opts = defaults opts,
            set_quotas : true   # if true, also sets all quotas (in parallel with start)
            cb         : required
        dbg = @dbg("start")
        async.parallel([
            (cb) =>
                if opts.set_quotas
                    dbg("setting all quotas")
                    @set_all_quotas(cb:cb)
                else
                    cb()
            (cb) =>
                dbg("issuing the start command")
                @_action(action: "start",  cb: cb)
        ], (err) =>
            opts.cb(err)
        )

    # restart project -- must be opened or running
    restart: (opts) =>
        opts = defaults opts,
            cb     : required
        dbg = @dbg("restart")
        dbg("get state")
        @state
            cb : (err, s) =>
                if err
                    dbg("error getting state - #{err}")
                    opts.cb(err)
                    return
                dbg("got state '#{s.state}'")
                if s.state == 'opened'
                    dbg("just start it")
                    @start(cb: opts.cb)
                    return
                else if s.state == 'running'
                    dbg("stop it")
                    @stop
                        cb : (err) =>
                            if err
                                opts.cb(err)
                                return
                            # return to caller since the once below
                            # can take a long time.
                            opts.cb()
                            # wait however long for stop to finish, then
                            # issue a start
                            @once 'opened', () =>
                                # now we can start it again
                                @start
                                    cb : (err) =>
                                        dbg("start finished -- #{err}")
                else
                    opts.cb("may only restart when state is opened or running or starting")

    # kill everything and remove project from this compute
    # node  (must be opened somewhere)
    close: (opts) =>
        opts = defaults opts,
            force  : false
            nosave : false
            cb     : required
        args = []
        dbg = @dbg("close(force:#{opts.force},nosave:#{opts.nosave})")
        if opts.force
            args.push('--force')
        if opts.nosave
            args.push('--nosave')
        dbg("force=#{opts.force}; nosave=#{opts.nosave}")
        @_action
            action : "close"
            args   : args
            cb     : opts.cb

    ensure_opened_or_running: (opts) =>
        opts = defaults opts,
            ignore_recv_errors : false
            cb     : required   # cb(err, state='opened' or 'running')
        state = undefined
        dbg = @dbg("ensure_opened_or_running")
        async.series([
            (cb) =>
                dbg("get state")
                @state
                    cb : (err, s) =>
                        if err
                            cb(err); return
                        state = s.state
                        dbg("got state #{state}")
                        if STATES[state].stable
                            cb()
                        else
                            dbg("wait for a stable state")
                            @once 'stable', (s) =>
                                state = s
                                dbg("got stable state #{state}")
                                cb()
            (cb) =>
                if state == 'running' or state == 'opened'
                    cb()
                else if state == 'closed'
                    dbg("opening")
                    @open
                        ignore_recv_errors : opts.ignore_recv_errors
                        cb : (err) =>
                            if err
                                cb(err)
                            else
                                @once 'opened', () =>
                                    dbg("it opened")
                                    state = 'opened'
                                    cb()
                else
                    cb("bug -- state=#{state} should be stable but isn't known")
        ], (err) => opts.cb(err, state))

    ensure_running: (opts) =>
        opts = defaults opts,
            cb : required
        state = undefined
        dbg = @dbg("ensure_running")
        async.series([
            (cb) =>
                dbg("get the state")
                @state
                    cb : (err, s) =>
                        if err
                            cb(err); return
                        state = s.state
                        if STATES[state].stable
                            cb()
                        else
                            dbg("wait for a stable state")
                            @once 'stable', (s) =>
                                state = s
                                cb()
            (cb) =>
                f = () =>
                    dbg("start running")
                    @start
                        cb : (err) =>
                            if err
                                cb(err)
                            else
                                @once 'running', () => cb()
                if state == 'running'
                    cb()
                else if state == 'opened'
                    f()
                else if state == 'closed'
                    dbg("open first")
                    @open
                        cb : (err) =>
                            if err
                                cb(err)
                            else
                                @once 'opened', () =>
                                    dbg("project opened; now start running")
                                    f()
                else
                    cb("bug -- state=#{state} should be stable but isn't known")
        ], (err) => opts.cb(err))

    ensure_closed: (opts) =>
        opts = defaults opts,
            force  : false
            nosave : false
            cb     : required
        dbg = @dbg("ensure_closed(force:#{opts.force},nosave:#{opts.nosave})")
        state = undefined
        async.series([
            (cb) =>
                dbg("get state")
                @state
                    cb : (err, s) =>
                        if err
                            cb(err); return
                        state = s.state
                        if STATES[state].stable
                            cb()
                        else
                            dbg("wait for a stable state")
                            @once 'stable', (s) =>
                                state = s
                                cb()
            (cb) =>
                f = () =>
                    dbg("close project")
                    @close
                        force  : opts.force
                        nosave : opts.nosave
                        cb : (err) =>
                            if err
                                cb(err)
                            else
                                @once 'closed', () => cb()
                if state == 'closed'
                    cb()
                else if state == 'opened'
                    f()
                else if state == 'running'
                    dbg("is running so first stop it")
                    @stop
                        cb : (err) =>
                            if err
                                cb(err)
                            else
                                dbg("now wait for it to be done stopping")
                                @once 'opened', () =>
                                    f()
                else
                    cb("bug -- state=#{state} should be stable but isn't known")
        ], (err) => opts.cb(err))

    # move project from one compute node to another one
    move: (opts) =>
        opts = defaults opts,
            target : undefined # hostname of a compute server; if not given, one (diff than current) will be chosen by load balancing
            force  : false     # if true, brutally ignore error trying to cleanup/save on current host
            cb     : required
        dbg = @dbg("move(target:'#{opts.target}')")
        if opts.target? and @host == opts.target
            dbg("project is already at target -- not moving")
            opts.cb()
            return
        async.series([
            (cb) =>
                async.parallel([
                    (cb) =>
                        dbg("determine target")
                        if opts.target?
                            cb()
                        else
                            exclude = []
                            if @host?
                                exclude.push(@host)
                            @compute_server.assign_host
                                exclude : exclude
                                cb      : (err, host) =>
                                    if err
                                        cb(err)
                                    else
                                        dbg("assigned target = #{host}")
                                        opts.target = host
                                        cb()
                    (cb) =>
                        dbg("first ensure it is closed/deleted from current host")
                        @ensure_closed
                            cb   : (err) =>
                                if err
                                    if not opts.force
                                        cb(err)
                                    else
                                        dbg("errors trying to close but force requested so proceeding -- #{err}")
                                        @ensure_closed
                                            force  : true
                                            nosave : true
                                            cb     : (err) =>
                                                dbg("second attempt error, but ignoring -- #{err}")
                                                cb()
                                else
                                    cb()


                ], cb)
            (cb) =>
                dbg("update database with new project location")
                @compute_server.database.set_project_host
                    project_id : @project_id
                    host       : opts.target
                    cb         : (err, assigned) =>
                        @assigned = assigned
                        cb(err)
            (cb) =>
                dbg("open on new host")
                @_set_host(opts.target)
                @open(cb:cb)
        ], opts.cb)

    destroy: (opts) =>
        opts = defaults opts,
            cb     : required
        dbg = @dbg("destroy")
        dbg("permanently delete everything about this projects -- complete destruction...")
        async.series([
            (cb) =>
                dbg("first ensure project is closed, forcing and not saving")
                @ensure_closed
                    force  : true
                    nosave : true
                    cb     : cb
            (cb) =>
                dbg("now remove project from btrfs stream storage too")
                @_set_host(undefined)
                @_action
                    action : "destroy"
                    cb     : cb
        ], (err) => opts.cb(err))

    stop: (opts) =>
        opts = defaults opts,
            cb     : required
        @dbg("stop")("will kill all processes")
        @_action
            action : "stop"
            cb     : opts.cb

    save: (opts) =>
        opts = defaults opts,
            max_snapshots : 50
            min_interval  : 4  # fail if already saved less than this many MINUTES (use 0 to disable) ago
            cb     : required
        dbg = @dbg("save(max_snapshots:#{opts.max_snapshots}, min_interval:#{opts.min_interval})")
        dbg("")
        # Do a client-side test to see if we have saved recently; much faster
        # than going server side trying and failing.
        if opts.min_interval and @_last_save and (new Date() - @_last_save) < 1000*60*opts.min_interval
            dbg("already saved")
            opts.cb("already saved within min_interval")
            return
        last_save_attempt = new Date()
        dbg('doing actual save')
        @_action
            action : "save"
            args   : ['--max_snapshots', opts.max_snapshots, '--min_interval', opts.min_interval]
            cb     : (err, resp) =>
                if not err
                    @_last_save = last_save_attempt
                opts.cb(err, resp)

    address: (opts) =>
        opts = defaults opts,
            cb : required
        dbg = @dbg("address")
        dbg("get project location and listening port -- will open and start project if necessary")
        address = undefined
        async.series([
            (cb) =>
                dbg("first ensure project is running")
                @ensure_running(cb:cb)
            (cb) =>
                dbg("now get the status")
                @status
                    cb : (err, status) =>
                        if err
                            cb(err)
                        else
                            if status.state != 'running'
                                dbg("something went wrong and not running ?!")
                                cb("not running")  # DO NOT CHANGE -- exact callback error is used by client code in the UI
                            else
                                dbg("status includes info about address...")
                                address =
                                    host         : @host
                                    port         : status['local_hub.port']
                                    secret_token : status.secret_token
                                cb()
        ], (err) =>
            if err
                opts.cb(err)
            else
                opts.cb(undefined, address)
        )

    copy_path: (opts) =>
        opts = defaults opts,
            path              : ""
            target_project_id : ""
            target_path       : ""        # path into project; if "", defaults to path above.
            overwrite_newer   : false     # if true, newer files in target are copied over (otherwise, uses rsync's --update)
            delete_missing    : false     # if true, delete files in dest path not in source, **including** newer files
            backup            : false     # make backup files
            exclude_history   : false
            timeout           : 5*60
            bwlimit           : undefined
            cb                : required
        dbg = @dbg("copy_path(#{opts.path} to #{opts.target_project_id})")
        dbg("copy a path using rsync from one project to another")
        if not opts.target_project_id
            opts.target_project_id = @project_id
        if not opts.target_path
            opts.target_path = opts.path
        args = ["--path", opts.path,
                "--target_project_id", opts.target_project_id,
                "--target_path", opts.target_path]
        if opts.overwrite_newer
            args.push('--overwrite_newer')
        if opts.delete_missing
            args.push('--delete_missing')
        if opts.backup
            args.push('--backup')
        if opts.exclude_history
            args.push('--exclude_history')
        if opts.bwlimit
            args.push('--bwlimit')
            args.push(opts.bwlimit)
        dbg("created args=#{misc.to_safe_str(args)}")
        target_project = undefined
        async.series([
            (cb) =>
                @ensure_opened_or_running
                    cb : cb
            (cb) =>
                if opts.target_project_id == @project_id
                    cb()
                else
                    dbg("getting other project and ensuring that it is already opened")
                    @compute_server.project
                        project_id : opts.target_project_id
                        cb         : (err, x) =>
                            if err
                                dbg("error ")
                                cb(err)
                            else
                                target_project = x
                                target_project.ensure_opened_or_running
                                    cb : (err) =>
                                        if err
                                            cb(err)
                                        else
                                            dbg("got other project on #{target_project.host}")
                                            args.push("--target_hostname")
                                            args.push(target_project.host)
                                            cb()
            (cb) =>
                containing_path = misc.path_split(opts.target_path).head
                if not containing_path
                    dbg("target path need not be made since is home dir")
                    cb(); return
                dbg("create containing target directory = #{containing_path}")
                if opts.target_project_id != @project_id
                    target_project._action
                        action  : 'mkdir'
                        args    : [containing_path]
                        timeout : opts.timeout
                        cb      : cb
                else
                    @_action
                        action  : 'mkdir'
                        args    : [containing_path]
                        timeout : opts.timeout
                        cb      : cb
            (cb) =>
                dbg("doing the actual copy")
                @_action
                    action  : 'copy_path'
                    args    : args
                    timeout : opts.timeout
                    cb      : cb
            (cb) =>
                if target_project?
                    dbg("target is another project, so saving that project (if possible)")
                    target_project.save
                        cb: (err) =>
                            if err
                                #  NON-fatal: this could happen, e.g, if already saving...  very slightly dangerous.
                                dbg("warning: can't save target project -- #{err}")
                            cb()
                else
                    cb()
        ], (err) =>
            if err
                dbg("error -- #{err}")
            opts.cb(err)
        )

    directory_listing: (opts) =>
        opts = defaults opts,
            path      : ''
            hidden    : false
            time      : false        # sort by timestamp, with newest first?
            start     : 0
            limit     : -1
            cb        : required
        dbg = @dbg("directory_listing")
        @ensure_opened_or_running
            cb : (err) =>
                if err
                    opts.cb(err)
                else
                    args = []
                    if opts.hidden
                        args.push("--hidden")
                    if opts.time
                        args.push("--time")
                    for k in ['path', 'start', 'limit']
                        args.push("--#{k}"); args.push(opts[k])
                    dbg("get listing of files using options #{misc.to_safe_str(args)}")
                    @_action
                        action : 'directory_listing'
                        args   : args
                        cb     : opts.cb

    read_file: (opts) =>
        opts = defaults opts,
            path    : required
            maxsize : 3000000    # maximum file size in bytes to read
            cb      : required   # cb(err, Buffer)
        dbg = @dbg("read_file(path:'#{opts.path}')")
        dbg("read a file or directory from disk")  # directories get zip'd
        @ensure_opened_or_running
            cb : (err) =>
                if err
                    opts.cb(err)
                else
                    @_action
                        action  : 'read_file'
                        args    : [opts.path, "--maxsize", opts.maxsize]
                        cb      : (err, resp) =>
                            if err
                                opts.cb(err)
                            else
                                opts.cb(undefined, new Buffer(resp.base64, 'base64'))

    get_quotas: (opts) =>
        opts = defaults opts,
            cb           : required
        @dbg("get_quotas")("lookup project quotas in the database")
        @compute_server.database.get_project_quotas
            project_id : @project_id
            cb         : opts.cb

    set_member_host: (opts) =>
        opts = defaults opts,
            member_host : required
            cb          : required
        # Ensure that member_host is a boolean for below; it is an integer -- 0 or >= 1 -- elsewhere.  But below
        # we very explicitly assume it is boolean (due to coffeescript not doing coercion).
        opts.member_host = opts.member_host > 0
        dbg = @dbg("set_member_host(member_host=#{opts.member_host})")
        # If member_host is true, make sure project is on a members only host, and if
        # member_host is false, make sure project is NOT on a members only host.
        current_host = undefined
        host_is_members_only = undefined
        async.series([
            (cb) =>
                dbg("get current project host")
                @compute_server.database.get_project_host
                    project_id : @project_id
                    cb         : (err, host) =>
                        current_host = host.host
                        cb(err)
            (cb) =>
                if not current_host?
                    host_is_members_only = false
                    cb()
                    return
                dbg("check if it is on a members-only host or not")
                @compute_server.database.is_member_host_compute_server
                    host : current_host
                    cb   : (err, x) =>
                        host_is_members_only = x
                        dbg("host_is_members_only = #{host_is_members_only}")
                        cb(err)
            (cb) =>
                if opts.member_host == host_is_members_only
                    # nothing to do
                    cb()
                    return
                @compute_server.database.get_all_compute_servers
                    cb : (err, servers) =>
                        if err
                            cb(err)
                            return
                        target = undefined
                        if opts.member_host
                            dbg("must move project to members_only host")
                            w = (x for x in servers when x.member_host)
                        else
                            dbg("move project off of members_only host")
                            w = (x for x in servers when not x.member_host)
                        if w.length == 0
                            cb("there are no #{if not opts.member_host then 'non-' else ''}members only hosts available")
                            return
                        target = misc.random_choice(w).host
                        dbg("moving project to #{target}...")
                        @move
                            target : target
                            force  : false
                            cb     : cb
        ], opts.cb)


    set_quotas: (opts) =>
        # Ignore any quotas that aren't in the list below: these are the only ones that
        # the local compute server supports.   It is convenient to allow the caller to
        # pass in additional quota settings.
        opts = misc.copy_with(opts, ['disk_quota', 'cores', 'memory', 'cpu_shares', 'network', 'mintime', 'member_host', 'cb'])
        dbg = @dbg("set_quotas")
        dbg("set various quotas")
        commands = undefined
        async.series([
            (cb) =>
                if not opts.member_host?
                    cb()
                else
                    dbg("ensure machine is or is not on member host")
                    @set_member_host
                        member_host : opts.member_host
                        cb          : cb
            (cb) =>
                dbg("get state")
                @state
                    cb: (err, s) =>
                        if err
                            cb(err)
                        else
                            dbg("state = #{s.state}")
                            commands = STATES[s.state].commands
                            cb()
            (cb) =>
                async.parallel([
                    (cb) =>
                        if opts.network? and commands.indexOf('network') != -1
                            dbg("update network: #{opts.network}")
                            @_action
                                action : 'network'
                                args   : if opts.network then [] else ['--ban']
                                cb     : cb
                        else
                            cb()
                    (cb) =>
                        if opts.mintime? and commands.indexOf('mintime') != -1
                            dbg("update mintime quota on project")
                            @_action
                                action : 'mintime'
                                args   : [opts.mintime]
                                cb     : (err) =>
                                    cb(err)
                        else
                            cb()
                    (cb) =>
                        if opts.disk_quota? and commands.indexOf('disk_quota') != -1
                            dbg("disk quota")
                            @_action
                                action : 'disk_quota'
                                args   : [opts.disk_quota]
                                cb     : cb
                        else
                            cb()
                    (cb) =>
                        if (opts.cores? or opts.memory? or opts.cpu_shares?) and commands.indexOf('compute_quota') != -1
                            dbg("compute quota")
                            args = []
                            for s in ['cores', 'memory', 'cpu_shares']
                                if opts[s]?
                                    if s == 'cpu_shares'
                                        opts[s] = Math.floor(opts[s])
                                    args.push("--#{s}")
                                    args.push(opts[s])
                            @_action
                                action : 'compute_quota'
                                args   : args
                                cb     : cb
                        else
                            cb()
                ], cb)
        ], (err) =>
            dbg("done setting quotas")
            opts.cb(err)
        )

    set_all_quotas: (opts) =>
        opts = defaults opts,
            cb : required
        dbg = @dbg("set_all_quotas")
        quotas = undefined
        async.series([
            (cb) =>
                dbg("looking up quotas for this project from database")
                @get_quotas
                    cb : (err, x) =>
                        quotas = x; cb(err)
            (cb) =>
                dbg("setting the quotas to #{misc.to_json(quotas)}")
                quotas.cb = cb
                @set_quotas(quotas)
        ], (err) => opts.cb(err))

