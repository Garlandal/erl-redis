%%%----------------------------------------------------------------------
%%%
%%% @copyright erl-redis 2010
%%%
%%% @author litao cheng <litaocheng@gmail.com>
%%% @doc redis distributed servers handle module
%%%     we use a sorted list store the hash ring
%%% @end
%%%
%%%----------------------------------------------------------------------
-module(redis_dist).
-author('litaocheng@gmail.com').
-vsn('0.1').
-include("redis.hrl").

-export([new/1]).
-export([get_server/2]).
-export([to_list/1]).

%% key is : 0..?KEY_RING_SPACE-1
%% the KeyA hosted by the server whose Hash >= KeyA
-define(KEY_RING_SPACE, (1 bsl 20)). 

%% @doc create new dist info
-spec new(ServerList :: [single_server()]) -> dist_server().
new(ServerList) ->
    % clear the duplicate elements
    Sets =
    lists:foldl(
        fun(S, Acc) ->
            sets:add_element(S, Acc)
        end,
    sets:new(), ServerList),

    SList1 = lists:sort(sets:to_list(Sets)),
    N = length(SList1),
    Range = ?KEY_RING_SPACE div N,
    ?DEBUG2("sorted list is ~p, range is ~p", [SList1, Range]),

    % split the ring space
    {_, SList2} =
    lists:foldl(
        fun(S, {KPos, Acc}) ->
            {KPos + Range,
                [{KPos, S} | Acc]}
        end,
    {0, []}, SList1),
    SList3 = lists:reverse(SList2),
    ?DEBUG2("servers with split key:~p", [SList3]),

    #dist_server{data = SList3}.

%% @doc get server from dist by the key
-spec get_server(Key :: key(), Dist :: dist_server()) -> 
    {'ok', server()} | 'none'.
get_server(Key, Dist) ->
    catch do_get_server(hash_key(Key), Dist).

%% @doc return the server list
-spec to_list(Dist :: dist_server()) -> [single_server()].
to_list(#dist_server{data = List}) ->
    {_, ServerList} = lists:unzip(List),
    ServerList.

%%------------------------------------------------------------------------------
%%
%% internal API
%%
%%------------------------------------------------------------------------------

%% hash key
hash_key(Key) ->
    erlang:phash2(Key, ?KEY_RING_SPACE).

%% do get server
do_get_server(Key, #dist_server{data = List}) ->
    [H | Tail] = List,
    lists:foreach(
        fun
            ({Hash, Server}) when Hash >= Key -> % found
                throw({ok, Server});
            (_) ->
                next
        end,
    List),
    % if reach there, it must be the frist one
    {_, Server} = H,
    {ok, Server}.

%%
%% eunit test
%%
-ifdef(TEST).

dist_test_() ->
    Srv1 = {localhost, 10001, 10},
    Srv2 = {localhost, 10002, 20},
    Srv3 = {localhost, 10003, 30},
    SL = [Srv1, Srv2, Srv3],
    Range = ?KEY_RING_SPACE div 3,
    Data = [{0, Srv1}, {Range, Srv2}, {Range*2, Srv3}],
    Dist = #dist_server{data = Data},

    [
        ?_assertEqual(Dist, new(SL)),

        ?_assertThrow({ok, Srv1}, do_get_server(0, Dist)),
        ?_assertThrow({ok, Srv2}, do_get_server(1, Dist)),
        ?_assertThrow({ok, Srv2}, do_get_server(Range - 1, Dist)),
        ?_assertThrow({ok, Srv2}, do_get_server(Range, Dist)),
        ?_assertThrow({ok, Srv3}, do_get_server(Range + 1, Dist)),
        ?_assertThrow({ok, Srv3}, do_get_server(Range*2 - 1, Dist)),
        ?_assertThrow({ok, Srv3}, do_get_server(Range*2, Dist)),
        ?_assertEqual({ok, Srv1}, do_get_server(Range*2 + 1, Dist)),
        ?_assertEqual({ok, Srv1}, do_get_server(Range*3 - 1, Dist)),

        ?_assertEqual(SL, to_list(Dist)),

        ?_assert(true)
    ].

-endif.
