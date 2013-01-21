-module(githubizer).
-author('chvanikoff <chvanikoff@gmail.com>').

%% API
-export([start/0]).

%% ===================================================================
%% API functions
%% ===================================================================

start() ->
	ok = ensure_started([crypto, public_key, ssl, ranch, cowboy, githubizer, inets]),
	ok = add_deploy_key().

%% ===================================================================
%% Internal functions
%% ===================================================================

ensure_started([]) -> ok;
ensure_started([App | Apps]) ->
	Msg = case application:start(App) of
		ok ->
			"started";
		{error, {already_started, App}} ->
			"was already started";
		Error ->
			io:format("Error starting ~p:~n~p~n", [App, Error]),
			throw(Error)
	end,
	io:format("~p " ++ Msg ++ "~n", [App]),
	ensure_started(Apps).

generate_ssh_key(Email) ->
	[] = os:cmd("ssh-keygen -t rsa -N \"\" -f ~/.ssh/githubizer -C \"" ++ Email ++ "\" -q"),
	os:cmd("ssh-add ~/.ssh/githubizer").

get_ssh_key(Email) ->
	Key = case os:cmd("if [ -f ~/.ssh/githubizer.pub ]; then cat ~/.ssh/githubizer.pub; else exit 0; fi") of
		[] ->
			generate_ssh_key(Email),
			os:cmd("cat ~/.ssh/githubizer.pub");
		Res ->
			Res
	end,
	[$\n | Out] = lists:reverse(Key),
	lists:reverse(Out).

add_deploy_key() ->
	{ok, [User, Email, Password, Repo]}
		= cfgsrv:get_multiple(["github.username", "github.email", "github.password", "github.repository"]),
	Key = get_ssh_key(Email),
	Url = "https://api.github.com/repos/" ++ User ++ "/" ++ Repo ++ "/keys",
	H = [{"Authorization","Basic " ++ base64:encode_to_string(User ++ ":" ++ Password)},
		{"Content-Type", "text/json"}],
	{ok, {{"HTTP/1.1", 200, "OK"}, _Headers, Body}} = httpc:request(get, {Url, H}, [], []),
	[Raw_key, _] = binary:split(list_to_binary(Key), list_to_binary(" " ++ Email)),
	case present_in_response(binary_to_list(Raw_key), Body) of
		true ->
			ok;
		false ->
			httpc:request(post, {Url, H, "application/x-www-form-urlencoded",
				"{\"title\": \"githubizer\", \"key\": \"" ++ Key ++ "\"}"}, [], []),
			io:format("~n~nDeploy key created~n"),
			ok
	end.

present_in_response(_Key, []) ->
	false;
present_in_response(Str, Response) ->

	case string:str(Response, Str) of
		0 ->
			false;
		_ ->
			true
	end.