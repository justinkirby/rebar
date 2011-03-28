%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% Copyright (c) 2011 Tuncer Ayaz
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% -------------------------------------------------------------------
-module(rebar_qc).

-export([qc/2]).

-include("rebar.hrl").

%% ===================================================================
%% Public API
%% ===================================================================


qc(Config, _AppFile) ->
    QCOpts = rebar_config:get(Config, qc_opts, []),
    QC = select_qc_lib(QCOpts),
    ?DEBUG("Selected QC library: ~p~n", [QC]),
    run(Config, QC, QCOpts -- [{qc, QC}]).

%% ===================================================================
%% Internal functions
%% ===================================================================

-define(QC_DIR, ".qc").

select_qc_lib(QCOpts) ->
    case proplists:get_value(qc_lib, QCOpts) of
        undefined ->
            detect_qc_lib();
        QC ->
            case code:ensure_loaded(QC) of
                {module, QC} ->
                    QC;
                {error, nofile} ->
                    ?ABORT("Configured QC library '~p' not available~n", [QC])
            end
    end.

detect_qc_lib() ->
    case code:ensure_loaded(proper) of
        {module, PropEr} ->
            PropEr;
        {error, nofile} ->
            case code:ensure_loaded(qc) of
                {module, EQC} ->
                    EQC;
                {error, nofile} ->
                    ?ABORT("No QC library available~n", [])
            end
    end.

setup_codepath() ->
    CodePath = code:get_path(),
    true = code:add_patha(qc_dir()),
    true = code:add_patha(ebin_dir()),
    CodePath.

run(Config, QC, QCOpts) ->
    ?DEBUG("QC Options: ~p~n", [QCOpts]),

    ok = filelib:ensure_dir(?QC_DIR ++ "/foo"),
    CodePath = setup_codepath(),
    ok = qc_compile(Config),
    case [QC:module(QCOpts, M) || M <- find_prop_mods()] of
        [] ->
            true = code:set_path(CodePath),
            ok;
        Errors ->
            ?ABORT("~p~n", [hd(Errors)])
    end.

find_prop_mods() ->
    Beams = rebar_utils:find_files(?QC_DIR, ".*\\.beam\$"),
    [M || M <- [rebar_utils:file_to_mod(Beam) || Beam <- Beams], has_prop(M)].

has_prop(Mod) ->
    lists:any(fun({F,_A}) -> lists:prefix("prop_", atom_to_list(F)) end,
              Mod:module_info(exports)).

qc_compile(Config) ->
    %% Obtain all the test modules for inclusion in the compile stage.
    %% Notice: this could also be achieved with the following
    %% rebar.config option: {qc_compile_opts, [{src_dirs, ["test"]}]}
    TestErls = rebar_utils:find_files("test", ".*\\.erl\$"),

    %% Compile erlang code to ?QC_DIR, using a tweaked config
    %% with appropriate defines, and include all the test modules
    %% as well.
    rebar_erlc_compiler:doterl_compile(qc_config(Config),
                                       ?QC_DIR, TestErls).

qc_dir() ->
    filename:join(rebar_utils:get_cwd(), ?QC_DIR).

ebin_dir() ->
    filename:join(rebar_utils:get_cwd(), "ebin").

qc_config(Config) ->
    EqcOpts = eqc_opts(),
    PropErOpts = proper_opts(),

    ErlOpts = rebar_config:get_list(Config, erl_opts, []),
    QCOpts = rebar_config:get_list(Config, qc_compile_opts, []),
    Opts = [{d, 'TEST'}, debug_info] ++
        ErlOpts ++ QCOpts ++ EqcOpts ++ PropErOpts,
    Config1 = rebar_config:set(Config, erl_opts, Opts),

    FirstErls = rebar_config:get_list(Config1, qc_first_files, []),
    rebar_config:set(Config1, erl_first_files, FirstErls).

eqc_opts() ->
    define_if('EQC', is_lib_avail(is_eqc_avail, eqc,
                                  "eqc.hrl", "QuickCheck")).

proper_opts() ->
    define_if('PROPER', is_lib_avail(is_proper_avail, proper,
                                     "proper.hrl", "PropEr")).

define_if(Def, true) -> [{d, Def}];
define_if(_Def, false) -> [].

is_lib_avail(DictKey, Mod, Hrl, Name) ->
    case erlang:get(DictKey) of
        undefined ->
            IsAvail = case code:lib_dir(Mod, include) of
                          {error, bad_name} ->
                              false;
                          Dir ->
                              filelib:is_regular(filename:join(Dir, Hrl))
                      end,
            erlang:put(DictKey, IsAvail),
            ?DEBUG("~s availability: ~p\n", [Name, IsAvail]),
            IsAvail;
        IsAvail ->
            IsAvail
    end.
