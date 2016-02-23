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
-module(zraft_dict_backend).
-author("dreyk").

-behaviour(zraft_backend).

-export([
    init/1,
    query/2,
    apply_data/2,
    apply_data/3,
    snapshot/1,
    snapshot_done/1,
    snapshot_failed/2,
    install_snapshot/2,
    expire_session/2]).

%% 用于维护具有 session 概念的 value 值
-record(session,{v,s}).

%% @doc init backend FSM
init(_) ->
    {ok,dict:new()}.

query(Fn,Dict) when is_function(Fn)->
    V = Fn(Dict),
    {ok,V};
query(Key,Dict) ->
    case dict:find(Key,Dict) of
        error->
            {ok,[Key],not_found};
        {ok,#session{v=V}}->
            {ok,[Key],{ok,V}};
        V->
            {ok,[Key],V}
    end.

%% @doc write data to FSM
%% 保存普通 key/value
apply_data({K,V},Dict)->
    Dict1 = dict:store(K,V,Dict),
    {ok,[K],Dict1}.

%% 保存具有 session 概念的 key/value
apply_data({K,V},Session,Dict)->
    Dict1 = dict:store(K,#session{v=V,s = Session},Dict),
    {ok,[K],Dict1}.

%% 获取匹配 Session 的 key 列表和移除这些 key 后的 dict
expire_session(Session,Dict)->
    %% T 中保存匹配 Session 的 key 列表
    %% D 中保存为匹配 Session 的 {key,value} 列表
    {T,D}=dict:fold(fun(K,V,{A1,A2})->
        case V of
            #session{s = Session}->
                {[K|A1],A2};
            _->
                {A1,[{K,V}|A2]}
        end end,{[],[]},Dict),
    {ok,T,dict:from_list(D)}.

%% @doc Prepare FSM to take snapshot async if it's possible otherwice return function to take snapshot immediately
snapshot(Dict)->
    Fun = fun(ToDir)->
        File = filename:join(ToDir,"state"),
        {ok,FD}=file:open(File,[write,raw,binary]),
        %% 1. 将 Dict 中的内容转换成 list 即 [{key,value},...]；
        %% 2. 将 list 中的每个数据转换成 binary 后，以 <<0:8,Size:64,V1/binary>> 格式写入文件
        lists:foreach(fun(E)->
            V1 = term_to_binary(E),
            Size = size(V1),
            Row = <<0:8,Size:64,V1/binary>>,
            file:write(FD,Row)
            end,dict:to_list(Dict)),
        ok = file:close(FD),
        ok
    end,
    {async,Fun,Dict}.

%% @doc Notify that snapshot has done.
snapshot_done(Dict)->
    {ok,Dict}.

%% @doc Notify that snapshot has failed.
snapshot_failed(_Reason,Dict)->
    {ok,Dict}.

%% @doc Read data from snapshot file or directiory.
%% 基于快照文件恢复数据
install_snapshot(Dir,_)->
    File = filename:join(Dir,"state"),
    {ok,FD}=file:open(File,[read,raw,binary]),
    Res = case read(FD,[]) of
        {ok,Data}->
            {ok,dict:from_list(Data)};
        Else->
            Else
    end,
    file:close(FD),
    Res.

read(FD,Acc)->
    case file:read(FD,9) of
        {ok,<<0:8,Size:64>>}->
            case file:read(FD,Size) of
                {ok,B}->
                    case catch binary_to_term(B) of
                        {'EXIT', _}->
                            {error,file_corrupted};
                        {K,V}->
                            read(FD,[{K,V}|Acc]);
                        _->
                            {error,file_corrupted}
                    end;
                _->
                    {error,file_corrupted}
            end;
        eof->
            {ok,Acc};
        _->
            {error,file_corrupted}
    end.