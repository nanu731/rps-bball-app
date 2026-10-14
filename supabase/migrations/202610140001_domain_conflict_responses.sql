-- Deliberate stale-domain conflicts must not masquerade as serialization failures.
-- PostgREST 14 retries 40001; PT409 returns HTTP 409 without replaying the command.
-- https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b
-- Append-only repair: replace only the pinned raises, retaining function identity,
-- ownership, signatures, search paths, SECURITY DEFINER flags and existing ACLs.
begin;
set local search_path=pg_catalog;
do $migration$
declare
  entry record;
  function_id oid;
  original_definition text;
  updated_definition text;
  original_metadata jsonb;
  updated_metadata jsonb;
  original_body text;
  original_defaults text;
  updated_defaults text;
  conflict_pattern constant text := $pattern$errcode[[:space:]]*=[[:space:]]*'40001'$pattern$;
begin
  for entry in select * from (values
    ('team_private.command_actor(uuid,bigint)', 1, '104e4eb56212dcdc20a4d5316ac49334438c63607a4f1b00eae45c7156b29fb7'),
    ('public.team_save_roster(uuid,text,text,bigint,uuid,bigint)', 1, '0a28b2b68d482ff1ab2029fec1cfd9e82976480d3265085ad71356cf6018f423'),
    ('public.team_archive_roster(uuid,uuid,bigint,bigint)', 1, 'f5a87b9303f148c173354a7a54e667ada9d1886ef8ff43a63748087d9b8803e3'),
    ('public.stats_create_game(uuid,uuid,date,text,text,text)', 1, '68c42f1047a7d768083bd09d3aa42dc6103d92df02846e05ed1d8dc83f565f69'),
    ('team_private.lock_stat(uuid,uuid,bigint)', 1, 'f7ac5a69be624ed13591f708f0e799df8a26cff4f23e15d9057971d8797b8834'),
    ('team_private.accept_stat(public.stat_versions,uuid,text)', 1, 'f2afc26395a95fdcddc58c9904e9b9b2c9380003e9a13e77385bc18da99b12ed'),
    ('public.stats_request_edit(uuid,uuid,bigint,text)', 1, '83e20ec9e68fa5e8470ee9602c86d5fc229e7b6942d8abb6e044d545310e6909'),
    ('public.stats_review_edit(uuid,uuid,bigint,boolean,text)', 3, 'b5b1e2ac5e94427d76884c6ec96015537c24149147cccca663602dc9fd3e1ba2'),
    ('public.stats_export_configure(uuid,text,integer,integer,integer,integer)', 1, '2ce61a9e9b0af7042f8954b5c6c8ee2d5dbebb45ca590e7d759b74c796404370'),
    ('public.play_open_draft(uuid,uuid,uuid)', 1, 'f70564cd4b96c3cd0c5086b6c522eb3a8143e28cccd43865168093f8f33d7313'),
    ('public.play_save_draft(uuid,uuid,bigint,text,jsonb)', 1, '6160ef09792ad4c50f1690e98318144b94da935a7365a4d71d097d12a2a2277d'),
    ('public.play_transition(uuid,uuid,bigint,text,text)', 1, '2abe3f05e72626270293002fdb3a12b5cbc3b7b6b20456bb57ecd3deacfefe95'),
    ('public.media_open_draft(uuid,uuid,text,uuid,uuid)', 1, 'a3d47c34cfd277be2147755d034e4e7a3f404b6325f11b75a890ce0c906eeed2'),
    ('public.media_save_draft(uuid,uuid,bigint,text,text,text)', 1, 'b38e8606d3955792f76c7ec363fcbae408da08ba548a543f71e31f9a955130d3'),
    ('public.media_transition(uuid,uuid,bigint,text,text)', 2, '99974f075b4a1e5158cfea70c6a816c94f98766ea9145b8513c625735f32bc5d'),
    ('public.play_recover_draft(uuid,uuid,bigint,uuid)', 1, 'd0dfca2c8acd0ddafcd322d1e0964f0f1cd219ed275cfc0e379de628d62ba886'),
    ('public.media_resume_draft(uuid,uuid,bigint,uuid)', 1, '5c2518f341d131b1f468ade3c059fb4b5f887dad0a18080f386cafc30fd937f6'),
    ('public.file_reserve(uuid,uuid,text,uuid,uuid,bigint,text,text,uuid)', 3, '7d0d417dc4e3f2e314b2d1c804b0972880616f6079bbddf6f898747011fb70e6'),
    ('public.file_save(uuid,uuid,bigint,text,text)', 1, 'e5587423e784912644679101cd532519ed7d6e9e4e81f38ae20d239ef6819028'),
    ('public.file_transition(uuid,uuid,bigint,text,text)', 2, 'd01bac3080944b0e5035c42b73cb1315874b85da8d8b8e803d80a6f0d8336375'),
    ('public.file_archive(uuid,uuid,uuid)', 1, '4591156f8c53e38a1468114c1af80f5fe3241575485c1846d4ec6a07988b2bcf'),
    ('public.file_upload_access(uuid,boolean)', 1, 'c943f4b26c4267a6842771083e418779531cc65a56d6917517c0b55ea4452531'),
    ('public.file_delivery(uuid,uuid,uuid)', 2, 'fe6e361960db93498b68d12238e2caeefb64a16d16b56feb3e7d8bd0d77d46c1'),
    ('public.file_worker_claim_upload(uuid,boolean)', 1, 'e023a145374cd1f1582f7ecc3aa691cb95e7825dbb855d7b55c6e41392fc0081'),
    ('public.file_worker_finish(uuid,bigint,text,text,jsonb,text)', 2, 'ed4e70b0f3c2dd8df5af68a2e50ef3444e159a1dafa8d592aab922f596d71988'),
    ('public.file_worker_missing(uuid)', 1, '68c8fb1139c8a18d8b0b850f2ba5672ff846d612951a8e6de7223beec0c7f5d1')
  ) as expected(signature, raise_count, source_sha256) loop
    function_id := to_regprocedure(entry.signature);
    if function_id is null then raise exception 'Missing expected TeamStats function: %', entry.signature; end if;
    -- Compare deparsed defaults: PostgreSQL's stored expression trees contain
    -- source-position metadata that CREATE OR REPLACE may legitimately change.
    select prosrc, to_jsonb(p) - 'prosrc' - 'proargdefaults', pg_get_expr(proargdefaults,0)
      into original_body, original_metadata, original_defaults
      from pg_proc p where oid=function_id;
    if encode(sha256(convert_to(original_body,'UTF8')),'hex') <> entry.source_sha256
      or (select count(*) from regexp_matches(original_body,conflict_pattern,'g')) <> entry.raise_count then
      raise exception 'TeamStats function differs from reviewed source: %', entry.signature;
    end if;
    original_definition := pg_get_functiondef(function_id);
    updated_definition := regexp_replace(original_definition,conflict_pattern,$replacement$errcode='PT409'$replacement$,'g');
    execute updated_definition;
    select to_jsonb(p) - 'prosrc' - 'proargdefaults', pg_get_expr(proargdefaults,0)
      into updated_metadata, updated_defaults from pg_proc p where oid=function_id;
    if updated_metadata is distinct from original_metadata
      or updated_defaults is distinct from original_defaults
      or pg_get_functiondef(function_id) is distinct from updated_definition then
      raise exception 'TeamStats conflict repair changed unexpected definition or permissions: %', entry.signature;
    end if;
  end loop;
end $migration$;
commit;
