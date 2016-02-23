
%% 由 candidate 发起，用来选举
-record(vote_request,{from,term,epoch,last_index,last_term}).
-record(vote_reply,{from_peer,epoch,request_term,peer_term,granted,commit}).

%% 由 leader 发起，用来分发日志
-record(append_entries, {
    term =0,
    epoch=0,
    from,
    request_ref,
    prev_log_index=0,
    prev_log_term=0,
    entries :: term(),
    commit_index=0}).
-record(append_reply, {
    epoch,
    request_ref,
    term = 0,
    from_peer,
    last_index=0,
    success=false,
    agree_index=0
    }).

-record(install_snapshot,{from,request_ref,term,epoch,index,data}).
-record(install_snapshot_reply,{epoch,request_ref,term,from_peer,addr,port,result,index}).

-define(UPDATE_CMD,update).
-define(BECOME_LEADER_CMD,become_leader).
-define(LOST_LEADERSHIP_CMD,lost_leadership).
-define(OPTIMISTIC_REPLICATE_CMD,optimistic_replicate).
-define(VOTE_CMD,vote).


-define(OP_CONFIG,1).
-define(OP_DATA,2).
-define(OP_NOOP,3).

-define(BLANK_CONF,blank).
-define(STABLE_CONF,stable).
-define(STAGING_CONF,staging).
-define(TRANSITIONAL_CONF,transitional).        %% 过渡状态

-define(ELECTION_TIMEOUT_PARAM,election_timeout).
-define(ELECTION_TIMEOUT,500).

-define(CLIENT_PING,'$zraftc_ping').
-define(CLIENT_CONNECT,'$zraftc_connect').
-define(CLIENT_CLOSE,'$zraftc_close').
-define(EXPIRE_SESSION,'$zraft_expire').
-define(DISCONNECT_MSG, disconnected).

-record(snapshot_info,{index=0,term=0,conf_index=0,conf=?BLANK_CONF}).

-record(log_op_result,{log_state,last_conf,result}).

-record(entry,{index,term,type,data,global_time=0}).

-record(pconf,{old_peers=[],new_peers=[]}).

%% id           -> peer_id() -> {atom(), node()}
%% voted_for    -> {atom(), node()} | undefined
%% current_term -> interger()
%% back_end     -> zraft_dict_backend
-record(raft_meta,{id,voted_for,current_term=0,back_end}).

%% 例如 {peer,{test1,test@Betty},1,true,0,1}
-record(peer,{id,next_index=1,has_vote=false,last_agree_index=0,epoch=0}).

%% first_index  -> interger()
%% last_index   -> interger()
%% last_term    -> interger()
%% commit_index -> interger()
-record(log_descr,{first_index,last_index,last_term,commit_index}).

-record(read,{from,request,watch=false,global_time}).

-record(fsm_stat,{session_number,watcher_number,tmp_count}).
-record(peer_start,{epoch,term,allow_commit,leader,back_end,log_state,snapshot_info,conf,conf_state,state_name,proxy_peer_stats=[],fsm_stat}).
-record(proxy_peer_stat,{peer_state,is_snapshoting}).
-record(swrite,{data,message_id,acc_upto,from,temporary=false}).%%write in session
-record(write,{data,from}).%%optimistic write

-record(swrite_reply,{sequence,data}).
-record(swrite_error,{sequence,leader,error}).
-record(sread_reply,{data,ref}).
-record(swatch_trigger,{ref,reason}).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-define(MINFO(S, As), ?debugFmt("[INFO] " ++ S, As)).
-define(MINFO(S), ?debugMsg("[INFO] " ++ S)).
-define(MWARNING(S, As), ?debugFmt("[WARNING] " ++ S, As)).
-define(MWARNING(S), ?debugMsg("[WARNING] " ++ S)).
-define(MERROR(S, As), ?debugFmt("[ERROR] " ++ S, As)).
-define(MERROR(S), ?debugMsg("[ERROR] " ++ S)).
-define(MDEBUG(S, As), ?debugFmt("[DEBUG] " ++ S, As)).
-define(MDEBUG(S), ?debugMsg("[DEBUG] " ++ S)).
-else.
-define(MINFO(S, As), lager:info(S, As)).
-define(MINFO(S), lager:info(S)).
-define(MWARNING(S, As), lager:warning(S, As)).
-define(MWARNING(S), lager:warning(S)).
-define(MERROR(S, As), lager:error(S, As)).
-define(MERROR(S), lager:error(S)).
-define(MDEBUG(S, As), lager:debug(S, As)).
-define(MDEBUG(S), lager:debug(S)).
-endif.