-- All in-game texts (Japanese). Edit the right-hand side to change a text.
Locales = {
    -- General
    not_ready            = 'Heist Creatorはまだ読み込み中です。少し待ってからもう一度お試しください。',
    not_loaded           = 'キャラクターが読み込まれていません。',
    no_permission        = 'この操作を行う権限がありません。',
    too_fast             = '操作が早すぎます。',
    invalid_data         = '無効なデータです。',
    invalid_state        = '現在この操作は行えません。',
    db_error             = 'データベースへの保存に失敗しました。',
    too_far              = '対象から離れすぎています。',
    too_far_npc          = 'ヘイストの受付NPCの近くにいる必要があります。',
    word_back            = '戻る',
    word_stages          = 'ステージ',
    word_guards          = 'ガード',
    word_loots           = '物色ポイント',
    word_rewards         = '報酬',

    -- Commands
    cmd_create           = 'Heist Creatorを開く (管理者)',
    cmd_setxp            = 'プレイヤーのヘイストXPを設定する (管理者)',
    cmd_param_player     = 'プレイヤーID',
    cmd_cancel           = 'ヘイストを中止する (リーダー) / ヘイストから離脱する (メンバー)',
    cmd_accept           = 'パーティーの招待を承諾する',
    cmd_decline          = 'パーティーの招待を拒否する',
    xp_set               = '%s のヘイストXPを %d に設定しました。',

    -- Creator validation
    err_name             = 'ヘイスト名を入力してください。',
    err_start            = '開始地点を設定してください。',
    err_extraction       = '脱出地点を設定してください。',
    err_stages           = 'ステージを1つ以上追加してください。',
    err_too_many         = '%sが多すぎます (最大 %d)。',
    err_stage_coords     = 'ステージ %d の位置が設定されていません。',
    err_stage_minigame   = 'ステージ %d のミニゲームが無効です。',
    err_item             = 'アイテム「%s」は存在しません。',
    err_guard_model      = 'ガード %d のモデルまたは武器が無効です。',
    err_guard_coords     = 'ガード %d の位置が設定されていません。',
    err_loot_coords      = '物色ポイント %d の位置が設定されていません。',
    err_rewards          = '物色ポイントがある場合は報酬を1つ以上設定してください。',
    heist_not_found      = 'ヘイストが見つかりません。',
    heist_busy           = 'このヘイストは現在進行中のため変更できません。',
    cooldown_reset       = 'クールダウンをリセットしました。',
    picker_help          = '[E] 位置を決定　[Backspace] キャンセル',

    -- Heist start requirements
    heist_in_progress    = 'このヘイストは他のクルーが進行中です。',
    already_in_heist     = 'すでにヘイストに参加しています。',
    not_in_heist         = 'ヘイストに参加していません。',
    need_players         = 'このヘイストには最低 %d 人が必要です。',
    too_many_players     = 'このヘイストは最大 %d 人までです。',
    need_police          = '警察官が不足しています (必要: %d人 / 現在: %d人)。',
    need_xp              = 'ヘイストXPが不足しています (必要: %d XP)。',
    member_need_xp       = '%s のヘイストXPが不足しています (必要: %d XP)。',
    member_not_ready     = '%s の準備ができていません。',
    cooldown_global      = 'このヘイストはクールダウン中です (残り %s)。',
    cooldown_player      = 'あなたはまだクールダウン中です (残り %s)。',
    member_cooldown      = '%s はまだクールダウン中です (残り %s)。',

    -- Heist flow
    heist_started        = 'ヘイスト「%s」を開始しました。',
    heist_completed      = 'ヘイスト「%s」成功！ +%d XP',
    heist_completed_bonus = 'ヘイスト「%s」成功！ +%d XP (パーティーボーナス +%d%%)',
    heist_completed_absent = 'ヘイスト「%s」は成功しましたが、脱出地点にいなかったためXPは獲得できませんでした。',
    heist_cancelled      = 'ヘイストは中止されました。',
    heist_timeout        = '時間切れ…ヘイスト失敗。',
    heist_left           = 'ヘイストから離脱しました。',
    heist_aborted        = 'ヘイストはサーバーにより中断されました。',
    heist_failed         = 'ヘイスト失敗。',

    -- Objectives
    obj_travel           = '開始地点へ向かえ',
    obj_stage            = 'ハッキングデバイスを使ってセキュリティを解除せよ',
    obj_loot             = 'マークされた場所を物色せよ',
    obj_extract          = '脱出地点で離脱せよ',
    step_stage           = 'ステージ %d / %d',
    step_loot            = '物色 %d / %d',
    blip_start           = 'ヘイスト開始地点',
    blip_extraction      = '脱出地点',

    -- Stages
    stage_default_label  = 'セキュリティを解除する',
    stage_in_use         = '他のメンバーが作業中です。',
    stage_failed         = '失敗した…もう一度試せ。',
    stage_failed_by      = '%s がセキュリティ解除に失敗した。',
    stage_done_by        = '%s がステージ %d / %d を突破した。',
    need_item            = '「%s」が %d 個必要です。',

    -- Loot
    loot_default_label   = '物色する',
    looting              = '物色中...',
    loot_empty           = 'ここにはもう何もない。',
    loot_in_use          = '他のメンバーが物色中です。',
    loot_cancelled       = '物色を中断した。',
    loot_nothing         = '何も見つからなかった。',
    loot_received        = '入手: %s',
    loot_dropped         = '持ちきれないアイテムを足元に落とした。',
    loot_done_by         = '%s が物色を完了した (%d / %d)。',

    -- Extraction
    extract_label        = '脱出する',
    extract_confirm_title = '脱出の確認',
    extract_confirm_text = 'まだ物色していない場所が %d 箇所残っています。このまま脱出しますか？',

    -- Party
    party_created        = 'パーティーを作成しました。',
    party_already_in     = 'すでにパーティーに参加しています。',
    party_none           = 'パーティーに参加していません。',
    party_not_leader     = 'パーティーリーダーのみ実行できます。',
    party_in_heist       = 'ヘイスト中は実行できません。',
    party_full           = 'パーティーが満員です。',
    party_invalid_target = 'プレイヤーが見つかりません。',
    party_target_busy    = 'そのプレイヤーはすでに別のパーティーに参加しています。',
    party_already_invited = 'そのプレイヤーにはすでに招待を送っています。',
    party_invite_sent    = '%s に招待を送りました。',
    party_invited        = '%s からパーティーに招待されました。/%s で承諾、/%s で拒否 (Heist HUDからも操作できます)。',
    party_no_invite      = '有効な招待がありません。',
    party_joined         = '%s がパーティーに参加しました。',
    party_you_joined     = 'パーティーに参加しました。',
    party_declined       = '%s が招待を拒否しました。',
    party_you_declined   = '招待を拒否しました。',
    party_left           = '%s がパーティーから離脱しました。',
    party_you_left       = 'パーティーから離脱しました。',
    party_new_leader     = 'あなたがパーティーリーダーになりました。',
    party_kicked         = 'パーティーから追放されました。',
    party_kick_done      = 'メンバーを追放しました。',

    -- NPC / police
    npc_target           = 'Heist HUDを開く',
    police_alert         = '通報: 「%s」で強盗が発生している模様。',
    police_blip          = '強盗発生',
}

---Returns a formatted text.
---@param key string
---@param ... any
---@return string
function L(key, ...)
    local text = Locales[key]
    if not text then return key end
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        return ok and formatted or text
    end
    return text
end
