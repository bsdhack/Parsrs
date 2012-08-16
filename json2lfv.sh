#! /bin/sh
#
# json2lfv.sh
#    JSONテキストから
#    階層インデックス付き値(trrr indexed value)ファイルへの変換器
#
# Usage   : json2tiv.sh [-dk<char>] [-dv<char>] [-lp<char>] [JSON_file]
# Options : -dk は各階層のキー名文字列間のデリミター指定(デフォルトは":")
#         : -dv はキー名インデックスと値の間のデリミター指定(デフォルトは" ")
#         : -lp は配列キーのプレフィックス文字列指定(デフォルトは空文字)
#
# Written by Rich Mikan(richmikan[at]richlab.org) / Date : Aug 17, 2012


ESC=$(printf '\033')             # 値のダブルクォーテーション(DQ)エスケープ用
LF=$(printf '\\\n_');LF=${LF%_}  # sed内で改行を変数として扱うためのもの

file=''
for arg in "$@"; do
  if [ \( "_${arg#-dk}" != "_$arg" \) -a \( -z "$file" \) ]; then
    dk=$(echo -n "_${arg#-dk}"           |
         od -A n -t o1                   |
         tr -d '\n'                      |
         sed 's/[[:blank:]]*$//;'        |
         sed 's/^[[:blank:]]\{1,\}137//' |
         sed 's/[[:blank:]]\{1,\}/\\/g'  )
  elif [ \( "_${arg#-dv}" != "_$arg" \) -a \( -z "$file" \) ]; then
    dv=$(echo -n "_${arg#-dv}"           |
         od -A n -t o1                   |
         tr -d '\n'                      |
         sed 's/[[:blank:]]*$//;'        |
         sed 's/^[[:blank:]]\{1,\}137//' |
         sed 's/[[:blank:]]\{1,\}/\\/g'  )
  elif [ \( "_${arg#-lp}" != "_$arg" \) -a \( -z "$file" \) ]; then
    lp=$(echo -n "_${arg#-lp}"           |
         od -A n -t o1                   |
         tr -d '\n'                      |
         sed 's/[[:blank:]]*$//;'        |
         sed 's/^[[:blank:]]\{1,\}137//' |
         sed 's/[[:blank:]]\{1,\}/\\/g'  )
  elif [ \( \( -f "$arg" \) -o \( -c "$arg" \) \) -a \( -z "$file" \) \) ]; then
    file=$arg
  elif [ \( "_$arg" = "_-" \) -a \( -z "$file" \) ]; then
    file=/dev/stdin
  else
    cat <<____USAGE > /dev/stderr
Usage   : json2tiv.sh [-dk<char>] [-dv<char>] [-lp<char>] [JSON_file]
Options : -dk は各階層のキー名文字列間のデリミター指定(デフォルトは":")
        : -dv はキー名インデックスと値の間のデリミター指定(デフォルトは" ")
        : -lp は配列キーのプレフィックス文字列指定(デフォルトは空文字)
____USAGE
    exit 1
  fi
done
[ -z "$file" ] && file='/dev/stdin'


# === データの流し込み ============================================= #
cat "$file"                                                          |
#                                                                    #
# === 値としてのダブルクォーテーション(DQ)をエスケープ ============= #
sed "s/\\\\\"/$ESC/g"                                                |
#                                                                    #
# === DQ始まり～DQ終わりの最小マッチングの前後に改行を入れる ======= #
sed "s/\(\"[^\"]*\"\)/$LF\1$LF/g"                                    |
#                                                                    #
# === DQ始まり以外の行の"{","}","[","]",":",","の前後に改行を挿入 == #
awk '                                                                \
$0~/^"/{                                                             \
  print;                                                             \
  next;                                                              \
}                                                                    \
{                                                                    \
  split($0, letter, "");                                             \
  for (i=1; i<=length(letter); i++) {                                \
    test=letter[i];                                                  \
    sub(/[\[\]{}:,]/, "", test);                                     \
    if (length(test)) {                                              \
      printf("%s", letter[i]);                                       \
    } else {                                                         \
      printf("\n%s\n", letter[i]);                                   \
    }                                                                \
  }                                                                  \
}                                                                    \
'                                                                    |
#                                                                    #
# === 無駄な空行は予め取り除いておく =============================== #
grep -v '^[[:blank:]]*$'                                             |
#                                                                    #
# === 行頭の記号を見ながら状態遷移させて処理(strict版*1) =========== #
# (*1 JSONの厳密なチェックを省略するならもっと簡素で高速にできる)    #
awk -v "keykey_delim=$dk" -v "keyval_delim=$dv" -v "list_prefix=$lp" \
'                                                                    \
BEGIN {                                                              \
  # 配列番号としてのキーのプレフィックス文字に指定があればそれにする \
  list_prefix=(length(list_prefix))?sprintf(list_prefix):"";         \
  # キー間のデリミター文字に指定があればそれにする                   \
  keykey_delim=(length(keykey_delim))?sprintf(keykey_delim):":";     \
  # キー-値間のデリミター文字に指定があればそれにする                \
  keyval_delim=(length(keyval_delim))?sprintf(keyval_delim):" ";     \
  # データ種別スタックの初期化                                       \
  datacat_stack[0]="";                                               \
  delete datacat_stack[0]                                            \
  # キー名スタックの初期化                                           \
  keyname_stack[0]="";                                               \
  delete keyname_stack[0]                                            \
  # スタックの深さを0に設定                                          \
  stack_depth=0;                                                     \
  # エラー終了検出変数を初期化                                       \
  _assert_exit=0;                                                    \
}                                                                    \
# "{"行の場合                                                        \
$0~/^{$/{                                                            \
  # データ種別スタックが空、又は最上位が"l0:配列(初期要素値待ち)"、  \
  # "l1:配列(値待ち)"、"h2:ハッシュ(値待ち)"であることを確認したら   \
  # データ種別スタックに"h0:ハッシュ(キー未取得)"をpush              \
  if ((stack_depth==0)                   ||                          \
      (datacat_stack[stack_depth]=="l0") ||                          \
      (datacat_stack[stack_depth]=="l1") ||                          \
      (datacat_stack[stack_depth]=="h2")  ) {                        \
    stack_depth++;                                                   \
    datacat_stack[stack_depth]="h0";                                 \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# "}"行の場合                                                        \
$0~/^}$/{                                                            \
  # データ種別スタックが空でなく最上位が"h0:ハッシュ(キー未取得)"、  \
  # "h3:ハッシュ(値取得済)"であることを確認したら                    \
  # データ種別スタック、キー名スタック双方をpop                      \
  # もしpop直後の最上位が"l0:配列(初期要素値待ち)"または             \
  # "l1:配列(値待ち)"だった場合には"l2:配列(値取得直後)"に変更       \
  # 同様に"h2:ハッシュ(値待ち)"だった時は"h3:ハッシュ(値取得済)"に   \
  if ((stack_depth>0)                       &&                       \
      ((datacat_stack[stack_depth]=="h0") ||                         \
       (datacat_stack[stack_depth]=="h3")  ) ) {                     \
    delete datacat_stack[stack_depth];                               \
    delete keyname_stack[stack_depth];                               \
    stack_depth--;                                                   \
    if (stack_depth>0) {                                             \
      if ((datacat_stack[stack_depth]=="l0") ||                      \
          (datacat_stack[stack_depth]=="l1")  ) {                    \
        datacat_stack[stack_depth]="l2"                              \
      } else if (datacat_stack[stack_depth]=="h2") {                 \
        datacat_stack[stack_depth]="h3"                              \
      }                                                              \
    }                                                                \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# "["行の場合                                                        \
$0~/^\[$/{                                                           \
  # データ種別スタックが空、又は最上位が"l0:配列(初期要素値待ち)"、  \
  # "l1:配列(値待ち)"、"h2:ハッシュ(値待ち)"であることを確認したら   \
  # データ種別スタックに"l0:配列(初期要素値待ち)"をpush、            \
  # およびキー名スタックに配列番号0をpush                            \
  if ((stack_depth==0)                   ||                          \
      (datacat_stack[stack_depth]=="l0") ||                          \
      (datacat_stack[stack_depth]=="l1") ||                          \
      (datacat_stack[stack_depth]=="h2")  ) {                        \
    stack_depth++;                                                   \
    datacat_stack[stack_depth]="l0";                                 \
    keyname_stack[stack_depth]=0;                                    \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# "]"行の場合                                                        \
$0~/^\]$/{                                                           \
  # データ種別スタックが空でなく最上位が"l0:配列(初期要素値待ち)"、  \
  # "l2:配列(値取得直後)"であることを確認したら                      \
  # データ種別スタック、キー名スタック双方をpop                      \
  # もしpop直後の最上位が"l0:配列(初期要素値待ち)"または             \
  # "l1:配列(値待ち)"だった場合には"l2:配列(値取得直後)"に変更       \
  # 同様に"h2:ハッシュ(値待ち)"だった時は"h3:ハッシュ(値取得済)"に   \
  if ((stack_depth>0)                       &&                       \
      ((datacat_stack[stack_depth]=="l0") ||                         \
       (datacat_stack[stack_depth]=="l2")  ) ) {                     \
    delete datacat_stack[stack_depth];                               \
    delete keyname_stack[stack_depth];                               \
    stack_depth--;                                                   \
    if (stack_depth>0) {                                             \
      if ((datacat_stack[stack_depth]=="l0") ||                      \
          (datacat_stack[stack_depth]=="l1")  ) {                    \
        datacat_stack[stack_depth]="l2"                              \
      } else if (datacat_stack[stack_depth]=="h2") {                 \
        datacat_stack[stack_depth]="h3"                              \
      }                                                              \
    }                                                                \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# ":"行の場合                                                        \
$0~/^:$/{                                                            \
  # データ種別スタックが空でなく                                     \
  # 最上位が"h1:ハッシュ(キー取得済)"であることを確認したら          \
  # データ種別スタック最上位を"h2:ハッシュ(値待ち)"に変更            \
  if ((stack_depth>0)                   &&                           \
      (datacat_stack[stack_depth]=="h1") ) {                         \
    datacat_stack[stack_depth]="h2";                                 \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# ","行の場合                                                        \
$0~/^,$/{                                                            \
  # 1)データ種別スタックが空でないことを確認                         \
  if (stack_depth==0) {                                              \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
  # 2)データ種別スタック最上位値によって分岐                         \
  # 2a)"l2:配列(値取得直後)"の場合                                   \
  if (datacat_stack[stack_depth]=="l2") {                            \
    # 2a-1)データ種別スタック最上位を"l1:配列(値待ち)"に変更         \
    datacat_stack[stack_depth]="l1";                                 \
    next;                                                            \
  # 2b)"h3:ハッシュ(値取得済)"の場合                                 \
  } else if (datacat_stack[stack_depth]=="h3") {                     \
    # 2b-1)データ種別スタック最上位を"h0:ハッシュ(キー未取得)"に変更 \
    datacat_stack[stack_depth]="h0";                                 \
    next;                                                            \
  # 2c)その他の場合                                                  \
  } else {                                                           \
    # 2c-1)エラー                                                    \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# それ以外の行(値の入っている行)の場合                               \
{                                                                    \
  # 1)データ種別スタックが空でないことを確認                         \
  if (stack_depth==0) {                                              \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
  # 2)DQ囲みになっている場合は予めそれを除去しておく                 \
  value=(match($0,/^".*"$/))?substr($0,2,RLENGTH-2):$0;              \
  # 3)データ種別スタック最上位値によって分岐                         \
  # 3a)"l0:配列(初期要素値待ち)"又は"l1:配列(値待ち)"の場合          \
  if ((datacat_stack[stack_depth]=="l0") ||                          \
        (datacat_stack[stack_depth]=="l1")  ) {                      \
    # 3a-1)キー名スタックと値を表示                                  \
    print_keys_and_value(value);                                     \
    # 3a-2)データ種別スタック最上位を"l2:配列(値取得直後)"に変更     \
    datacat_stack[stack_depth]="l2";                                 \
  # 3b)"h0:ハッシュ(キー未取得)"の場合                               \
  } else if (datacat_stack[stack_depth]=="h0") {                     \
    # 3b-1)値をキー名としてキー名スタックにpush                      \
    keyname_stack[stack_depth]=value;                                \
    # 3b-2)データ種別スタック最上位を"h1:ハッシュ(キー取得済)"に変更 \
    datacat_stack[stack_depth]="h1";                                 \
  # 3c)"h2:ハッシュ(値待ち)"の場合                                   \
  } else if (datacat_stack[stack_depth]=="h2") {                     \
    # 3c-1)キー名スタックと値を表示                                  \
    print_keys_and_value(value);                                     \
    # 3a-2)データ種別スタック最上位を"h3:ハッシュ(値取得済)"に変更   \
    datacat_stack[stack_depth]="h3";                                 \
  # 3d)その他の場合                                                  \
  } else {                                                           \
    # 3d-1)エラー                                                    \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# 最終処理                                                           \
END {                                                                \
  if (_assert_exit) {                                                \
    print "Invalid JSON format" > "/dev/stderr";                     \
    line1="keyname-stack:";                                          \
    line2="datacat-stack:";                                          \
    for (i=1;i<=stack_depth;i++) {                                   \
      line1=line1 sprintf("{%s}",keyname_stack[i]);                  \
      line2=line2 sprintf("{%s}",datacat_stack[i]);                  \
    }                                                                \
    printf("%s\n%s\n",line1,line2) > "/dev/stderr";                  \
  }                                                                  \
  exit _assert_exit;                                                 \
}                                                                    \
# キー名一覧と値を表示する関数                                       \
function print_keys_and_value (str) {                                \
  line=keyname_stack[1];                                             \
  for (i=2;i<=stack_depth;i++) {                                     \
    s = (substr(datacat_stack[i],1,1)=="l")?list_prefix:"";          \
    line=line keykey_delim s keyname_stack[i];                       \
  }                                                                  \
  printf("%s\n",line keyval_delim str);                              \
}                                                                    \
'                                                                    |
#                                                                    #
# === 値としてのダブルクォーテーション(DQ)のエスケープ解除 ========= #
sed "s/$ESC/\\\\\"/g"