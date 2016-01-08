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
-module(zraft_log_util).
-author("dreyk").

-include("zraft.hrl").

-export([
    append_request/6
]).

append_request(Epoch,CurentTerm,CommitIndex,PrevIndex, PrevTerm,Entries) ->
    Commit = min(CommitIndex, PrevIndex + length(Entries)),
    #append_entries{
        epoch = Epoch,
        term = CurentTerm,
        entries = Entries,
        prev_log_index = PrevIndex,
        prev_log_term = PrevTerm,
        commit_index = Commit}.
