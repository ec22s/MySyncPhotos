# MySyncPhotos

2026.11.1[「JAWS-UG&thinsp;佐賀&thinsp;#34 ハック・ザ・メディア 〜佐賀に&thinsp;AI&thinsp;はあうんか？〜」](https://jawsug-saga.connpass.com/event/400996/)の&thinsp;LT&thinsp;②でデモした&thinsp;iOS&thinsp;アプリ「&thinsp;MySyncPhotos&thinsp;」と、その作成過程で構築したバックエンド（&thinsp;AWS Blocks&thinsp;）のソース

<br>

- LTについて

  - タイトル「&thinsp;Kiro + AWS Blocks&thinsp;で試すモバイルアプリ開発」

  - [スライドPDFへのリンク](https://drive.google.com/file/d/1Eh595voIHceFtW906nH6BtZQafaijJSH)

<br>

- アプリとバックエンドの概要

  - スライドを参照して下さい&thinsp;🙇

  - Kiro&thinsp;が出力したバックエンドとデータフローのダイアグラムが&thinsp;[docs](docs/)&thinsp;にあります

    - データフロー図で&thinsp;iPad&thinsp;が「uploader」、iPhone&thinsp;が「viewer」になっていますが特に意味はなく（そういうケースで多くテストしていただけ）、iOS&thinsp;端末の種別による違いはないです

<br>

- リポジトリ全体について

  - ほぼ&thinsp;Kiro&thinsp;が作ってひととおり動いた時の状態です. LT&thinsp;の主眼が&thinsp;AI&thinsp;で作ることにあったため

  - アプリ用ソースの一部[（MySyncPhotos/Sources/MySyncPhotos/Generated）](MySyncPhotos/Sources/MySyncPhotos/Generated)は&thinsp;AWS Blocks&thinsp;がバックエンドの設定から自動生成するもの

  - AWS&thinsp;アカウントなどハードコーディングされていた一部の設定項目をアスタリスクでマスクしました. 実行時は適宜変更が必要です

<br>

- ローカルでの動作確認

  - 今回利用した&thinsp;AWS Blocks&thinsp;は&thinsp;<u>AWS&thinsp;アカウント不要でローカルに&thinsp;AWS&thinsp;サービスのモックを作れる</u>&thinsp;便利なフレームワークで、ローカルで試すだけなら&thinsp;AWS&thinsp;は使いません

  - AWS Blocks&thinsp;の&thinsp;API&thinsp;を&thinsp;LAN&thinsp;内の&thinsp;iOS&thinsp;端末から呼ぶため、アプリソース内に `192.168.xxx.xxx` がハードコーディングされています. LAN&thinsp;環境に合わせ適宜変更して下さい

<br>

- バックエンドのデプロイについて

  - AWS Blocks&thinsp;で構築したものを&thinsp;AWS&thinsp;にデプロイするには `AWS CLI` と `AWS CDK` が必要です. 詳細は&thinsp;<u>[公式ドキュメント](https://docs.aws.amazon.com/blocks/latest/devguide/deploy-to-aws.html)</u>&thinsp;を参照

<br>

- 動作確認した環境

  - アプリ：iPhone SE3 (iOS 26.7.1), iPad mini 6th (iPadOS 27.2) いずれも実機

  - ローカルのバックエンド：

    ```
    $ $SHELL --version
    GNU bash, version 5.3.20(1)-release (x86_64-apple-darwin25.5.0)

    $ node --version
    v22.23.2

    $ npm --version
    12.0.2
    ```

<br>

- 質問等の宛先

  - <u>[プロフィールページ](https://github.com/ec22s)</u>&thinsp;にあるメールアドレスへお願いします
