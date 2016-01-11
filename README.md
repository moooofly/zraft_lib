# zraft_lib

Erlang [raft consensus protocol](https://raftconsensus.github.io) implementation .

特性支持：
> - 运行时成员关系的重配置
> - 基于快照的日志截断
> - 端到端的异步 RPC
> - 可插拔式状态机
> - 最优日志复制策略
> - 基于内核 sendfile 命令实现的快照传输
> - 客户端会话
> - 临时数据维护（如临时节点一般）
> - 数据变更触发器

## Erlang 架构

![schema](docs/img/schema.png?raw=true)

## 通用配置

配置示例

```
[{zraft_lib,
     [{snapshot_listener_port,0},
      {election_timeout,500},
      {request_timeout,1000},
      {snapshot_listener_addr,"0,0,0,0"},
      {snapshot_backup,false},
      {log_dir,"./data"},
      {snapshot_dir,"./data"},
      {max_segment_size,10485760},
      {max_log_count,1000}]},
 {lager,
     [{error_logger_hwm,100},
      {error_logger_redirect,true},
      {crash_log_date,"$D0"},
      {crash_log_size,10485760},
      {crash_log_msg_size,65536},
      {handlers,
          [{lager_file_backend,
               [{file,"./log/console.log"},
                {level,info},
                {size,10485760},
                {date,"$D0"},
                {count,5}]},
           {lager_file_backend,
               [{file,"./log/error.log"},
                {level,error},
                {size,10485760},
                {date,"$D0"},
                {count,5}]}]},
      {crash_log,"./log/crash.log"},
      {crash_log_count,5}]},
 {sasl,[{sasl_error_logger,false}]}].
```

部分参数说明：
> - "**election_timeout**" - **`Follower`** 发起新一轮选举所需的超时时间（以毫秒为单位，默认为 500 毫秒）
> - "**request_timeout**" - **`Leader`** 等待来自 Follower 的复制成功 RPC 应答的超时事件（以毫秒为单位，默认为 *2*election_timeout*）
> - "**snapshot_listener_port**" - 用于快照传输的默认端口（即监听端口，设置为 0 表示可以使用任意空闲端口）
> - "**snapshot_listener_addr**" - 用于快照传输的绑定地址（即监听地址）
> - "**snapshot_backup**" - 如果打开该选项，则全部快照将会被归档
> - "**log_dir**" - 指定保存 RAFT 日志和元数据的目录
> - "**snapshot_dir**" - 保存快照文件的目录
> - "**max_segment_size**" - 以字节为单位的日志块最大尺寸（若达到该尺寸限制则创建新的日志文件块）
> - "**max_log_count**" - 每当达到 "max_log_count" 个条目时，将会自动启动快照/日志切割处理

## 创建并配置 RAFT 集群

```
zraft_client:create(Peers,BackEnd).
```

参数说明：
> - `Peers` - 集群中将会包含的 peer 列表，例如
	`[{test1,'test1@host1'},{test1,'test2@host2'},{other_test,'test3@host3'}]`.
> - `BackEnd` - 用于处理用户请求的模块名

可能的返回值：
 - `{ok,Peers}` - 集群被成功创建
 - `{error,{PeerID,Error}}` - PeerID 由于 "Error" 错误无法创建
 - `{error,[{PeerID,Error}]}` - Peers 无法被创建
 - `{error,Reason}` - 集群已经被创建，但是新配置在被应用时由于 "Reason" 原因失败了


## 基本操作

#### Light Session Object.

Light session object 用于跟踪当前 raft 集群状态，例如，leader 状态，失效 peers 状态，等等...

通过 **PeerID** 创建会话对象：

```
zraft_client:light_session(PeerID,FailTimeout,ElectionTimeout).
```

参数说明：
> - `PeerID` - 由集群管理并分配的 peer ID
> - `FailTimeout` - 若我们发现某个 peer 已经失效了，那么在本轮xx周期内，我们将不会发送任何请求给该 peer
> - `ElectionTimeout` - 若我们发现某个 peer 不再是 leader 了，那么在本轮xx周期内，我们将不再发送任何请求给该 peer

可能的返回值：
- `LightSession` - Light Session object
- `{error,Reason}` - 无法读取集群配置信息


通过 **PeerId 列表**创建会话对象：

```
zraft_client:light_session(PeersList,FailTimeout,ElectionTimeout).
```

该函数不会尝试从集群中读取配置信息

#### 写操作

```
zraft_client:write(PeerID,Data,Timeout).

```

参数说明：
> - `PeerID` - PeerID
> - `Data` - 与 BackEnd 模块相对应的的请求数据

可能的返回值：
> - `{Result,LeaderPeerID}` - 将请求 Data 作用到 BackEnd 模块后得到的结果；LeaderPeerID 为集群中当前的 leader ID
> - `{error,Error}` - 执行失败。典型原因为 timeout 或者 noproc


通过 session object 进行写

```
zraft_client:write(LightSessionObj,Data,Timeout).
```

参数说明：
> - `LightSessionObj` - Light Sesssion Object.
> - `Data` - 与 BackEnd 模块相对应的的请求数据

可能的返回值：
> - `{Result,LightSessionObj}` - 将请求 Data 作用到 BackEnd 模块后得到的结果；LeaderPeerID 为集群中当前的 leader ID
> - `{error,Error}` - 执行失败。典型原因为 timeout 或者 all_failed ；`all_failed` 意味着不存在处于 alive 状态的 peer

```
警告：在该请求被执行期间，Data 可能会作用到 backend 模块上两次
```

#### 读请求

```
zraft_client:query(PeerID,Query,Timeout).

```

参数说明：
> - `PeerID` - PeerID.
> - `Query` - Request Data specific for backend module.

可能的返回值：
> - `{Result,LeaderPeerID}` - Result 为查询的结果；LeaderPeerID 为当前的 leader ID
> - `{error,Error}` - 执行失败。典型原因为 timeout 或者 noproc


或者基于 light session object 读取数据：

```
zraft_client:query(LaghtSessionObj,Query,Timeout).
```

可能的返回值：
> - `{Result,LightSessionObj}` - Result 为查询的结果；LightSessionObj 为被更新的 session object
> - `{error,Error}` - 执行失败。典型原因为 timeout 或者 all_failed ；`all_failed` 意味着不存在处于 alive 状态的 peer


#### 配置变更

```
zraft_client:set_new_conf(Peer,NewPeers,OldPeers,Timeout).
```

## 会话的用途

You can create long lived session to RAFT cluster. It can be used triggers and temporary datas.
可以在 RAFT 集群中创建长生命周期的会话。可以将这种会话用作触发器和临时数据。

```
zraft_session:start_link(PeerOrPeers,SessionTimeout)->{ok,Session}.
```

If first parameter is PeerID other available Peer will be readed from that Peer.
如果第一个参数为 PeerID ，那么其他 Peer 将从该 Peer 读取xx

#### 针对 Data 和 Ephemeral data 的写

```
zraft_session:write(Session,Data, Temporary, Timeout).
```
If Temporary is true then data will be deleted after session wil be expired.
如果设置 Temporary 为 true ，那么 data 将会在会话过期后被删除

#### 针对 Data 的读以及 watcher 设置

```
zraft_session:query(Session,Query,Watch,Timeout).
```

Watch is trigger reference that will be triggered after future changes.Trigger will be triggered only once, if you need new trigger you must data again.
Watch 机制属于一种触发器引用，在将来某个时刻发生变更时被触发。触发器仅会被触发一次，如果你需要新的触发器，你必须重新 watch 

示例程序：
```
zraft_session:query(S1,1,my_watcher,1000).
%%Result = not_found.
zraft_session:write(S2,{1,2},1000).
receive
     {swatch_trigger,my_watcher,Reason}->
          %%Data changed. Change Reason is data_chaged or leader chaged.
          ok
end.
zraft_session:query(S1,1,my_watcher,1000). %%watch again
```


##Standalone Server.

You can use it for tests from erlang console.

https://github.com/dreyk/zraft


## TODO:
- Write External API documentation.
- Add backend based on ets table
- Add "watcher" support (notify client about backend state changes).


