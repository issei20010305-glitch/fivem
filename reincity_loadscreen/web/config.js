// re:IN city ロード画面の設定
// Everything you are likely to change is in this file.
window.LOADSCREEN = {
    // ロゴ下の一文 / line under the logo
    tagline: '雨の街へ、ようこそ。',

    // 画面右の縦書き / vertical text on the right edge
    vertical: '雨音に耳をすませば、街が目を覚ます。',

    // 進行度に応じて表示するメッセージ (from = 進行度 0〜1)
    // status text shown for each part of the loading progress
    statuses: [
        { from: 0.00, text: '雨雲を呼んでいます' },
        { from: 0.25, text: '街に雨を降らせています' },
        { from: 0.55, text: '傘をひらいています' },
        { from: 0.85, text: 'まもなく到着します' },
    ],

    // 雨 / rain
    rain: {
        density: 1.0, // 雨の量 (0.5 = 少なめ, 2 = 土砂降り)
        wind: 0.12,   // 雨の傾き (0 = 真下)
    },

    // 雨音 (音声ファイル不要・ブラウザで生成) / synthesized rain sound
    sound: {
        enabled: true,
        volume: 0.22, // 0〜1
    },
};
