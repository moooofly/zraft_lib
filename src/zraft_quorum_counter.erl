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
-module(zraft_quorum_counter).
-author("dreyk").

-behaviour(gen_server).

%% API
-export([start_link/1]).


%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-export([
    set_conf/3,
    sync/2,
    set_state/2
]).

-include("zraft.hrl").


%%
%% raft -> zraft_consensus 进程 pid
%% conf_id -> 
%% conf_state -> blank | stable | staging | transitional
%% epoch_qourum -> 
%% index_quorum -> 
%% vote_quorum -> 标识 has_vote 的 peer 是否为大多数
%% raft_state -> follower | candidate | leader
-record(state, {raft,conf_id,old,new,conf_state,epoch_qourum,index_quorum,vote_quorum,raft_state}).

set_conf(P,Conf,ConfState)->
    gen_server:cast(P,{set_conf,Conf,ConfState}).

%% PeerState ->  #peer{} ，例如 {peer,{test1,test@Betty},1,true,0,1}
sync(P,PeerState)->
    gen_server:cast(P,PeerState).

set_state(P,StateName)->
    gen_server:cast(P,{raft_state,StateName}).

%% Raft -> zraft_consensus 进程 pid
start_link(Raft) ->
    gen_server:start_link(?MODULE, [Raft], []).


init([Raf]) ->
    {ok, #state{
        raft = Raf,
        old = [],
        new = [],
        conf_state = ?STABLE_CONF,
        conf_id = 0,
        epoch_qourum = 0,
        index_quorum = 0,
        vote_quorum = false,
        raft_state = follower}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({raft_state,StateName},State)->
    {noreply,State#state{raft_state = StateName}};
handle_cast({set_conf,?BLANK_CONF,ConfState},State)->
    State1 = State#state{
        conf_id = 0,
        conf_state = ConfState,
        vote_quorum = true,
        epoch_qourum = 0,
        index_quorum = 0,
        new = [],
        old = []
    },
    {noreply,State1};
handle_cast({set_conf,{ConfID,#pconf{new_peers = New,old_peers = Old}},ConfState},State)->
    State1 = change_conf(ConfID,Old,New,ConfState,State),
    {noreply,State1};

%% 变更 peer 状态信息
handle_cast(#peer{}=P,State)->
    State1 = change_peer(P,State),
    {noreply,State1};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.


terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% 变更 peer 状态信息
change_peer(#peer{id = ID}=P,State=#state{old = O,new=N})->
    lager:info("[moooofly] change_peer --->", []),
    %% update(Key,Value,Dict)
    O1 = update(ID,P,O),
    N1 = update(ID,P,N),
    State1 = State#state{old = O1,new = N1},
    State2 = change_vote(State1),
    State3 = change_epoch(State2),
    change_last_agree_index(State3).

change_conf(ConfID,OldPeer,NewPeers,ConfState,State=#state{old = O1,new = N1})->
    O2 = merge(OldPeer,O1),
    N2 = merge(NewPeers,N1),
    State1 = State#state{old = O2,new = N2,conf_id = ConfID,conf_state = ConfState},
    State2 = change_vote(State1),
    State3 = change_epoch(State2),
    change_last_agree_index(State3).

%% 变更 epoch
change_epoch(State=#state{epoch_qourum = E,raft_state = leader,conf_id = ConfID})->
    case quorumMin(State,#peer.epoch) of
        E->
            State;
        E1->
            lager:info("[moooofly]     change_epoch ---> sync_peer(...,{sync_epoch,...}), E1 = ~p", [E1]),
            zraft_consensus:sync_peer(State#state.raft,{sync_epoch,ConfID,E1}),
            State#state{epoch_qourum = E1}
    end;
change_epoch(State)->
    State.

%% 变更 index
change_last_agree_index(State=#state{index_quorum = I,raft_state = leader,conf_id = ConfID})->
    case quorumMin(State,#peer.last_agree_index) of
        I->
            State;
        I1->
            lager:info("[moooofly]     change_last_agree_index ---> sync_peer(...,{sync_index,...}), I1 = ~p", [I1]),
            zraft_consensus:sync_peer(State#state.raft,{sync_index,ConfID,I1}),
            State#state{index_quorum = I1}
    end;
change_last_agree_index(State)->
    State.

%% 变更 vote
change_vote(State=#state{vote_quorum = V,raft_state = candidate,conf_id = ConfID})->
    case quorumAll(State,#peer.has_vote) of
        V->     %% 与原 vote 状态相同
            State;
        V1->    %% 与原 vote 状态不同
            lager:info("[moooofly]     change_vote ---> sync_peer(...,{sync_vote,...}), V1 = ~p", [V1]),
            zraft_consensus:sync_peer(State#state.raft,{sync_vote,ConfID,V1}),
            State#state{vote_quorum = V1}
    end;
change_vote(State)->
    State.

create_peers(Peers)->
    lists:foldr(fun(PeerID,Acc)->
        [{PeerID,#peer{id = PeerID,epoch = 0,has_vote = false,last_agree_index = 0,next_index = 1}}|Acc]
    end,[],Peers).

merge([P1|D1], [{P2,_}=E2|D2]) when P1 < P2 ->
    [{P1,#peer{id=P1,epoch = 0,has_vote = false,last_agree_index = 0,next_index = 1}}|merge(D1, [E2|D2])];
merge([P1|D1], [{P2,_}|D2]) when P1 > P2 ->
    merge([P1|D1], D2);
merge([_P1|D1], [E2|D2]) ->	%P1 == P2
    [E2|merge(D1, D2)];
merge([], _D2)-> [];
merge(D1, [])->
    create_peers(D1).

quorumMin(#state{conf_id = 0}, _GetIndex) ->
    0;
quorumMin(#state{conf_state = ConfState,old = Old,new = New}, GetIndex) ->
    case ConfState of
        ?TRANSITIONAL_CONF ->
            erlang:min(
                quorumMin1(Old, GetIndex),
                quorumMin1(New, GetIndex)
            );
        _ ->
            quorumMin1(Old, GetIndex)
    end.

%% 判定 has_vote 的 peer 是否过半数
%% GetIndex -> #peer.has_vote 即 4
quorumAll(#state{conf_id = 0},_GetIndex)->
    true;
quorumAll(#state{conf_state = ConfState,old = Old,new = New}, GetIndex) ->
    case ConfState of
        ?TRANSITIONAL_CONF ->   %% 过渡状态
            quorumAll1(Old, GetIndex) andalso quorumAll1(New, GetIndex);
        _ ->
            quorumAll1(Old, GetIndex)
    end.

quorumMin1([], _GetIndex) ->
    0;
quorumMin1(Peers, GetIndex) ->
    {Vals, Count} = quorumMin(Peers,GetIndex, 0,[]),
    Vals1 = lists:sort(Vals),
    At = erlang:trunc((Count - 1) / 2),
    lists:nth(At + 1, Vals1).

quorumMin([], _GetIndex, Count,Acc) ->
    {Acc, Count};
quorumMin([{_,Peer} | T2], GetIndex, Count,Acc)->
    V = element(GetIndex,Peer),
    quorumMin(T2,GetIndex, Count + 1,[V|Acc]).


quorumAll1([],_GetIndex) ->
    true;
quorumAll1(Peers, GetIndex) ->
    quorumAll(Peers,GetIndex,0,0).

%% 判定已经 vote 的 peer 是否过半数
quorumAll([], _GetIndex, Count,TrueCount) ->
    TrueCount >= (erlang:trunc(Count / 2) + 1);
quorumAll([{_, Peer} | T2], GetIndex,Count,TrueCount) -> %% ID1==ID2
    V = element(GetIndex,Peer),
    V1 = if
             V->
                 TrueCount+1;
             true->
                 TrueCount
         end,
    quorumAll(T2,GetIndex, Count + 1,V1).

%% 将 K/V 值更新到 Dict 中
%% 1.Dict 中的内容按照 Key 从小到大排序
%% 2.更新时插入的位置取决于 Key 的大小
%% 3.若 K/V 中的 Key 小于 Dict 中的任何一个 Key 则不插入
update(Key,V,[{K,_}=E|Dict]) when Key > K ->
    [E|update(Key,V, Dict)];
update(Key,V, [{K,_Val}|Dict]) when Key == K ->
    [{Key,V}|Dict];
update(_,_,Dict)->
    Dict.