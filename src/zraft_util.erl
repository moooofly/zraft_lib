%% -------------------------------------------------------------------
%% @author Gunin Alexander <guninalexander@gmail.com>
%% Copyright (c) 2015 Gunin Alexander.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(zraft_util).
-author("dreyk").

%% API
-export([
    peer_name/1,
    escape_node/1,
    node_name/1,
    get_env/2,
    random/1,
    start_app/1,
    del_dir/1,
    make_dir/1,
    node_addr/1,
    miscrosec_timeout/1,
    gen_server_cancel_timer/1,
    gen_server_cast_after/2,
    peer_id/1,
    set_test_dir/1,
    clear_test_dir/1,
    is_expired/2,
    random/2,
    now_millisec/0,
    timestamp_millisec/1,
    count_list/1,
    cycle_exp/1,
    peer_name_to_dir_name/1,
    format/2
]).

%% 将当前系统时间换算成 ms 表示的时间
now_millisec()->
   {Mega,S,Micro} = os:timestamp(),
   (Mega*1000000+S)*1000+(Micro div 1000).

%% 将指定时间换算成 ms 表示的时间
timestamp_millisec({Mega,S,Micro})->
    (Mega*1000000+S)*1000+(Micro div 1000).

%% 生成 peer 的名字字符串
peer_name({Name,Node}) when is_atom(Name)->
    atom_to_list(Name)++"-"++node_name(Node);
peer_name({Name,Node})->
    binary_to_list(base64:encode(term_to_binary(Name)))++"-"++node_name(Node).

node_name(Node)->
    escape_node(atom_to_list(Node)).

%% 将 Node 中的 @ 和 . 转成 _
escape_node([])->
    [];
escape_node([$@|T])->
    [$_|escape_node(T)];
escape_node([$.|T])->
    [$_|escape_node(T)];
escape_node([E|T])->
    [E|escape_node(T)].


get_env(Key, Default) ->
    case application:get_env(zraft_lib, Key) of
        {ok, Value} ->
            Value;
        _ ->
            Default
    end.

%% @doc Generate "random" number X, such that `0 <= X < N'.
%% 生成一个比 0 大但比 N 小的随机数
-spec random(pos_integer()) -> pos_integer().
random(N) ->
    erlang:phash2(erlang:statistics(io), N).
%% 增加自定义前缀的版本
-spec random(term(),pos_integer()) -> pos_integer().
random(Prefix,N) ->
    erlang:phash2({Prefix,erlang:statistics(io)}, N).

%% 删除目录及其下的所有内容
del_dir(Dir)->
    case del_dir1(Dir) of
        {error,enoent}->
            ok;
        ok->
            ok;
        Else->
            Else
    end.
del_dir1(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} ->  %% 对应 Dir 为目录的情况
            lists:foreach(fun(F) ->
                del_dir1(filename:join(Dir, F)) end, Files),
            %% 删除目录（要求目录下面必须为空）
            file:del_dir(Dir);
        _ ->    %% 对应 enoent（Dir 不存在） | enotdir（Dir 为文件） | eacces（权限不足） 的情况
            %% [Note] 这里不管是文件还是目录，直接进行了删除处理
            file:delete(Dir),
            file:del_dir(Dir)
    end.

%% 创建目录 Dir（自动创建目录层级中缺失的部分）
make_dir(undefined)->
    exit({error,dir_undefined});
make_dir("undefined"++_)->
    exit({error,dir_undefined});
make_dir(Dir) ->
    case make_safe(Dir) of
        ok ->
            ok;
        {error, enoent} ->  %% 创建目录层级中不存在的部分
            S1 = filename:split(Dir),
            S2 = lists:droplast(S1),
            case make_dir(filename:join(S2)) of
                ok ->
                    make_safe(Dir);
                Else -> %% 无法处理的错误 eacces | enospc | enotdir
                    Else
            end;
        Else -> %% 无法处理的错误 eacces | enospc | enotdir
            Else
    end.
make_safe(Dir)->
    %% 创建目录，若创建具有多级目录结构的目录，则要求所有父目录都存在
    case file:make_dir(Dir) of
        ok->
            ok;
        {error,eexist}->    %% 已存在名为 Dir 的目录
            ok;
        Else->      %% eacces（权限不足） | enoent（目录层级中有不存在的部分） | 
            Else    %% enospc（空间不足） | enotdir（目录层级中有不是目录的部分）
    end.

%% Based on: https://github.com/rabbitmq/rabbitmq-server/blob/master/src/rabbit_queue_index.erl#L542
%% 获取由 36 进制字符构成的原子
peer_name_to_dir_name(PeerId) ->
    %% 这里得到的 Num 将是一个超大整数值
    <<Num:128>> = erlang:md5(term_to_binary(PeerId)),
    %% 以 36 进制格式化 Num 值
    list_to_atom(format("~.36B", [Num])).

%% Taken from: https://github.com/rabbitmq/rabbitmq-server/blob/master/src/rabbit_misc.erl#L649
format(Fmt, Args) ->
    lists:flatten(io_lib:format(Fmt, Args)).

%% 获取节点名对应的地址
node_addr(Node)->
    L = atom_to_list(Node),
    case string:tokens(L,"@") of
        [_,"nohost"]->
            "127.0.0.1";
        [_,Addr]->
            Addr;
        _->
            "127.0.0.1"
    end.

%% [Note] 单词拼写错误？
miscrosec_timeout(Timeout) when is_integer(Timeout)->
    Timeout*1000;
miscrosec_timeout(Timeout)->
    Timeout.

gen_server_cast_after(Time, Event) ->
    erlang:start_timer(Time,self(),{'$zraft_timeout', Event}).
gen_server_cancel_timer(Ref)->
    case erlang:cancel_timer(Ref) of
        false ->
            receive {timeout, Ref, _} -> 0
            after 0 -> false
            end;
        RemainingTime ->
            RemainingTime
    end.

%% from_peer_addr() -> {peer_id(), pid()}
%%                  -> {{peer_name(), node()}, pid()}
%%                  -> {{atom(), node()}, pid()}
%% ID -> peer_id() -> {atom(), node()}
-spec peer_id(zraft_consensus:from_peer_addr())->zraft_consensus:peer_id().
peer_id({ID,_})->
    ID.

%% 测试函数

set_test_dir(Dir)->
    del_dir(Dir),
    ok = make_dir(Dir),
    application:set_env(zraft_lib,log_dir,Dir),
    application:set_env(zraft_lib,snapshot_dir,Dir).
clear_test_dir(Dir)->
    application:unset_env(zraft_lib,log_dir),
    application:unset_env(zraft_lib,snapshot_dir),
    del_dir(Dir).

%% 过期或超时 判定，返回 true | {false, infinity} | {false, MilliSecondsLeft }
is_expired(_Start,infinity)->
    {false,infinity};
is_expired(Start,Timeout)->
    T1 = Timeout*1000,
    case timer:now_diff(os:timestamp(),Start) of
        T2 when T2 >= T1 ->
            true;
        T2->
            {false,((T1-T2) div 1000)+1}
    end.

cycle_exp(T)->
    cycle_exp(os:timestamp(),T).
cycle_exp(Start,T)->
    case is_expired(Start,T) of
        true->
            ok;
        {false,T1}->
            %%io:format("s ~p~n",[T1]),
            cycle_exp(os:timestamp(),T1)
    end.

%% 应用启动（递归启动依赖应用）
start_app(App)->
    start_app(App,ok).
start_app(App,ok) ->
    io:format("starting ~s~n",[App]),
    case application:start(App) of
        {error,{not_started,App1}}->
            io:format("    should start ~s first...~n",[App1]),
            start_app(App,start_app(App1,ok));
        {error, {already_started, App}}->
            io:format("    already start ~s~n",[App]),
            ok;
        Else->
            io:format("    new start ~s - ~p~n",[App,Else]),
            Else
    end;
start_app(_,Error) ->
    Error.

%% [Note] 用途？
count_list([])->
    [];
count_list([{E1,C1}|T])->
    count_list(E1,C1,T).

count_list(E1,C1,[{E1,C2}|T])->
    count_list(E1,C1+C2,T);
count_list(E1,C1,[{E2,C2}|T])->
    [{E1,C1}|count_list(E2,C2,T)];
count_list(E1,C1,[])->
    [{E1,C1}].