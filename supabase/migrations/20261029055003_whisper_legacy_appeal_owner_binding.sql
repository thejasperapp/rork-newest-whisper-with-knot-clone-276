alter policy whisper_legacy_appeal_private_v2 on public.whisper_liar_appeals using(public.whisper_is_reviewer() or author_id=auth.uid());
