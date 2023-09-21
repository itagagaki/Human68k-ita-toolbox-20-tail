* tail - output tail of input
*
* Itagaki Fumihiko 07-Feb-93  Create.
* 1.0
* Itagaki Fumihiko 19-Feb-93  標準入力が切り替えられていても端末から^Cや^Sなどが効くようにした
* Itagaki Fumihiko 19-Feb-93  シークできないデバイスからの -<N>l が正常に動作しないバグを修正
* Itagaki Fumihiko 22-Feb-93  +<N> の結果が 1 ずれているバグ（仕様のバグ）を修正
* Itagaki Fumihiko 24-Feb-93  シーク可能かどうかの判定方法を変更
* 1.1
* Itagaki Fumihiko 08-Jan-94  RAW CHAR デバイスを入力すると無条件ループに入るバグを修正
* Itagaki Fumihiko 09-Jan-94  Brush up.
* Itagaki Fumihiko 29-Aug-94  Brush up.
* Itagaki Fumihiko 10-Oct-94  countの形式を拡張.
* 1.2
*
* Usage: tail [ -qvBCZ ] { [ {+-}<#>[ckl][-<#>[ckl]] | -[<#>]r ] [ -- ] [ <ファイル> ] } ...

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref isdigit
.xref atou
.xref strlen
.xref strfor1
.xref strip_excessive_slashes

IMPLEMENT_FOLLOW	equ	0

STACKSIZE	equ	2048
OUTBUF_SIZE	equ	8192
READSIZE	equ	8192

DEFAULT_COUNT	equ	10

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_q			equ	0	*  -q
FLAG_v			equ	1	*  -v
FLAG_B			equ	2	*  -B
FLAG_C			equ	3	*  -C
FLAG_Z			equ	4	*  -Z
FLAG_from_top		equ	5
FLAG_byte_unit		equ	6
FLAG_follow		equ	7
FLAG_reverse		equ	8
FLAG_head		equ	9
FLAG_output_byte_unit	equ	10
FLAG_add_newline	equ	11
FLAG_can_seek		equ	12
FLAG_eof		equ	13

.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	bss_top(pc),a6
		lea	stack_bottom(a6),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin(a6)
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.B : フラグ
		move.l	#DEFAULT_COUNT,count(a6)
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		move.b	1(a0),d0
		beq	decode_opt_done

		bsr	isdigit
		beq	decode_opt_done

		cmp.b	#'r',d0
		bne	decode_opt_loop1_1

		tst.b	2(a0)
		beq	decode_opt_done
decode_opt_loop1_1:
		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		cmp.b	#'q',d0
		beq	option_q_found

		cmp.b	#'v',d0
		beq	option_v_found

		cmp.b	#'B',d0
		beq	option_B_found

		cmp.b	#'C',d0
		beq	option_C_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

option_q_found:
		bset	#FLAG_q,d5
		bclr	#FLAG_v,d5
		bra	set_option_done

option_v_found:
		bset	#FLAG_v,d5
		bclr	#FLAG_q,d5
		bra	set_option_done

option_B_found:
		bset	#FLAG_B,d5
		bclr	#FLAG_C,d5
		bra	set_option_done

option_C_found:
		bset	#FLAG_C,d5
		bclr	#FLAG_B,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
		bsr	parse_count
	*
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering(a6)
		beq	stdout_is_block_device		*  -- ブロック・デバイスである
	*
	*  出力はキャラクタ・デバイス
	*
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	outbuf_ok

		btst	#FLAG_B,d5
		bne	outbuf_ok

		bset	#FLAG_C,d5
		bra	outbuf_ok

stdout_is_block_device:
	*
	*  stdoutはブロック・デバイス
	*
		*  出力バッファを確保する
		*
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a4				*  A4 : 出力バッファの先頭アドレス
		movea.l	d0,a5				*  A5 : 出力バッファのポインタ
outbuf_ok:
	*
	*  入力バッファを確保する
	*
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		cmp.l	#READSIZE,d0
		blt	insufficient_memory

		move.l	d0,inpbuf_size(a6)
		bsr	malloc
		bmi	insufficient_memory
inpbuf_ok:
		move.l	d0,inpbuf(a6)
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin(a6)
		bmi	stdin_ok

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
stdin_ok:
		lea	msg_header2(pc),a1
		st	show_header(a6)
		btst	#FLAG_v,d5
		bne	do_files

		sf	show_header(a6)
		btst	#FLAG_q,d5
		bne	do_files

		cmp.l	#1,d7
		shi	show_header(a6)
do_files:
	*
	*  開始
	*
		tst.l	d7
		beq	do_stdin
for_file_loop:
		subq.l	#1,d7
		movea.l	a0,a3
		bsr	strfor1
		exg	a0,a3
		cmpi.b	#'-',(a0)
		bne	do_file

		tst.b	1(a0)
		bne	do_file
do_stdin:
		lea	msg_stdin(pc),a0
		move.l	stdin(a6),d1
		bmi	open_fail

		bsr	tail_one
		bra	for_file_continue

do_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
		move.l	d0,d1
		bmi	open_fail

		bsr	tail_one
		move.w	d1,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
for_file_continue:
		movea.l	a3,a0
		bsr	parse_count
		tst.l	d7
		beq	all_done

		lea	msg_header1(pc),a1
		bra	for_file_loop

all_done:
		moveq	#0,d6
exit_program:
		move.l	stdin(a6),d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
exit_program_1:
		move.w	d6,-(a7)
		DOS	_EXIT2

open_fail:
		lea	msg_open_fail(pc),a2
		bra	werror_exit_2
****************************************************************
parse_count:
parse_count_loop:
		tst.l	d7
		beq	parse_count_done

		move.b	1(a0),d0
		cmpi.b	#'+',(a0)
		beq	parse_count_0

		cmpi.b	#'-',(a0)
		bne	parse_count_done

		cmp.b	#'r',d0
		bne	parse_count_0

		tst.b	2(a0)
		bne	parse_count_break

		moveq	#-1,d1
		sf	d0				*  skip atou
		bra	parse_count_2

parse_count_0:
.if IMPLEMENT_FOLLOW
		cmp.b	#'f',d0
		bne	parse_count_1

		tst.b	2(a0)
		bne	parse_count_break

		moveq	#10,d1
		sf	d0				*  skip atou
		bra	parse_count_2
.endif
parse_count_1:
		bsr	isdigit
		bne	parse_count_break

		st	d0				*  do atou
parse_count_2:
		bclr	#FLAG_from_top,d5
		cmpi.b	#'-',(a0)
		beq	parse_count_n

		bset	#FLAG_from_top,d5
parse_count_n:
		addq.l	#1,a0
		tst.b	d0
		beq	parse_count_unit

		bsr	atou
		bne	bad_count
parse_count_unit:
		move.l	d1,count(a6)
		subq.l	#1,d7
		bclr	#FLAG_byte_unit,d5
		bclr	#FLAG_follow,d5
		bclr	#FLAG_reverse,d5
		bclr	#FLAG_head,d5
		bclr	#FLAG_output_byte_unit,d5
		move.b	(a0),d0
		beq	parse_count_7

		cmp.b	#'l',d0
		beq	parse_count_3

		cmp.b	#'c',d0
		beq	parse_count_c

		cmp.b	#'k',d0
		beq	parse_count_k

		btst	#FLAG_from_top,d5
		bne	parse_count_4

		cmp.b	#'r',d0
		bne	parse_count_4

		bset	#FLAG_reverse,d5
		bra	parse_count_5

parse_count_k:
		cmp.l	#$400000,d1
		bhs	bad_count

		lsl.l	#8,d1
		lsl.l	#2,d1
		move.l	d1,count(a6)
parse_count_c:
		bset	#FLAG_byte_unit,d5
		bset	#FLAG_output_byte_unit,d5
parse_count_3:
		addq.l	#1,a0
		move.b	(a0),d0
		beq	parse_count_7
parse_count_4:
.if IMPLEMENT_FOLLOW
		cmp.b	#'f',d0
		bne	parse_count_not_follow

		bset	#FLAG_follow,d5
		bra	parse_count_5
parse_count_not_follow:
.endif
		cmp.b	#'-',d0
		bne	parse_count_7

		addq.l	#1,a0
		bsr	atou
		bne	bad_count

		move.l	d1,head_count(a6)
		bset	#FLAG_head,d5
		bclr	#FLAG_output_byte_unit,d5
		move.b	(a0),d0
		beq	parse_count_7

		cmp.b	#'l',d0
		beq	parse_count_5

		cmp.b	#'c',d0
		beq	parse_count_head_c

		cmp.b	#'k',d0
		bne	parse_count_7

		cmp.l	#$400000,d1
		bhs	bad_count

		lsl.l	#8,d1
		lsl.l	#2,d1
		move.l	d1,head_count(a6)
parse_count_head_c:
		bset	#FLAG_output_byte_unit,d5
parse_count_5:
		addq.l	#1,a0
parse_count_7:
		tst.b	(a0)+
		beq	parse_count_loop
bad_count:
		lea	msg_illegal_count(pc),a0
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

parse_count_break:
		cmpi.b	#'-',(a0)
		bne	parse_count_done

		cmpi.b	#'-',1(a0)
		bne	parse_count_done

		tst.b	2(a0)
		bne	parse_count_done

		addq.l	#3,a0
		subq.l	#1,d7
parse_count_done:
		rts
****************************************************************
* tail_one
****************************************************************
tail_one:
		sf	cr_pending(a6)
		tst.b	show_header(a6)
		beq	tail_one_1

		move.l	a0,-(a7)
		movea.l	a1,a0
		bsr	puts
		movea.l	(a7),a0
		bsr	puts
		lea	msg_header3(pc),a0
		bsr	puts
		movea.l	(a7)+,a0
tail_one_1:
		bsr	check_input_device
		bsr	do_tail_one
		bsr	flush_cr
flush_outbuf:
		move.l	d0,-(a7)
		tst.b	do_buffering(a6)
		beq	flush_done

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free(a6),d0
		exg	a1,a4
		bsr	write
		exg	a1,a4
		movea.l	a4,a5
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
flush_done:
		move.l	(a7)+,d0
		rts

flush_cr:
		tst.b	cr_pending(a6)
		beq	flush_cr_return

		move.l	d0,-(a7)
		moveq	#CR,d0
		bsr	putc
		move.l	(a7)+,d0
flush_cr_return:
		rts
****************************************************************
do_tail_one:
		bclr	#FLAG_eof,d5
		btst	#FLAG_from_top,d5
		beq	tail_RelBot
****************
tail_RelTop:
		move.l	count(a6),d2
		subq.l	#1,d2
		bls	output_remainder_0
		*
		*  count-1unit読みとばす
		*
		btst	#FLAG_can_seek,d5
		beq	skip_head

		tst.b	ignore_from_ctrlz(a6)
		bne	skip_head

		tst.b	ignore_from_ctrld(a6)
		bne	skip_head

		btst	#FLAG_byte_unit,d5
		beq	skip_head

		move.l	d2,d0
		bsr	seek_from_top
		cmp.l	d2,d0
		beq	output_remainder_0

		bsr	seek_to_phigical_eof
		bmi	seek_fail

		cmp.l	d2,d0
		bhs	seek_fail
tail_done_0:
		rts

skip_head:
		bsr	read_some			*  D4.L := 有効バイト数
		beq	tail_done_0

		btst	#FLAG_byte_unit,d5
		bne	skip_head_byte
skip_head_line_loop:
		move.b	(a1)+,d0
		subq.l	#1,d4
		cmp.b	#LF,d0
		bne	skip_head_line_continue

		subq.l	#1,d2
		beq	output_remainder
skip_head_line_continue:
		tst.l	d4
		bne	skip_head_line_loop
skip_head_continue:
		btst	#FLAG_eof,d5
		beq	skip_head
tail_done_1:
		rts

skip_head_byte:
		sub.l	d4,d2
		bhi	skip_head_continue

		neg.l	d2
		adda.l	d4,a1
		move.l	d2,d4
		suba.l	d4,a1
		bra	output_remainder
****************
tail_RelBot:
		btst	#FLAG_can_seek,d5
		beq	tail_RelBot_Unseekable
****************
tail_RelBot_Seekable:
		tst.l	count(a6)
		beq	tail_done_1
		*
		*  論理的なファイルの終わりにシークする
		*
		tst.b	ignore_from_ctrlz(a6)
		bne	seek_to_logical_eof

		tst.b	ignore_from_ctrld(a6)
		bne	seek_to_logical_eof

		bsr	seek_to_phigical_eof
		bra	seek_to_logical_eof_done

seek_to_logical_eof:
		bsr	read_some
		move.l	d0,d2				*  D2.L := 読み込んだバイト数
		beq	seek_to_logical_eof_2		*  D0.L == 0

		btst	#FLAG_eof,d5
		beq	seek_to_logical_eof

		*  EOF以降読み進んでしまった分戻る
		move.l	d4,d0
		sub.l	d2,d0
seek_to_logical_eof_2:
		bsr	seek_relative
seek_to_logical_eof_done:
		bmi	seek_fail

		bclr	#FLAG_eof,d5
		*  ここで，D0.L : 現在の位置

		btst	#FLAG_byte_unit,d5
		bne	tail_RelBot_Seekable_Byte
****************
tail_RelBot_Seekable_Line:
		move.l	d0,d2				*  D2.L : 現在の位置
		moveq	#0,d3				*  D3.L : 先走り量
		move.l	count(a6),d4			*  D4.L : count
		bsr	tail_file_lines_read
		beq	tail_done_2

		btst	#FLAG_reverse,d5
		bne	tail_RelBot_Seekable_ReverseLine

		cmpi.b	#LF,-1(a1)
		beq	tail_RelBot_Seekable_Line_1

		subq.l	#1,d4		*  改行で終了していない最後の半端な行をカウントする
tail_RelBot_Seekable_Line_1:
		move.l	d3,d0
		bsr	backward_lines
		bne	tail_done_2
tail_RelBot_Seekable_Line_loop:
		bsr	tail_file_lines_read
		beq	output_remainder_0

		move.l	d3,d0
		bsr	backward_lines
		bmi	tail_done_2
		bne	output_remainder_0
		bra	tail_RelBot_Seekable_Line_loop
****************
tail_RelBot_Seekable_Byte:
		cmp.l	count(a6),d0
		bls	tail_RelBot_Seekable_Byte_1

		move.l	count(a6),d0
tail_RelBot_Seekable_Byte_1:
		neg.l	d0
		bsr	seek_relative
		bmi	seek_fail
output_remainder_0:
		bsr	read_some			*  D4.L := 有効バイト数
		beq	tail_done_2
output_remainder:
		bsr	output_buf
		bmi	tail_done_2

		btst	#FLAG_eof,d5
		beq	output_remainder_0
tail_done_2:
		rts
****************
tail_RelBot_Seekable_ReverseLine:
		move.l	d3,d0
		bset	#FLAG_add_newline,d5
		cmpi.b	#LF,-1(a1)
		bne	Seekable_ReverseLine_1
Seekable_ReverseLine_continue:
		bclr	#FLAG_add_newline,d5
Seekable_ReverseLine_1:
		bsr	put_backward_lines
		beq	tail_done_2
Seekable_ReverseLine_ReadLoop:
		bsr	tail_file_lines_read
		move.l	d3,d0
		beq	Seekable_ReverseLine_last

		bsr	backward_a_line
		bne	Seekable_ReverseLine_PutOne

		add.l	d3,d6
		bra	Seekable_ReverseLine_ReadLoop

Seekable_ReverseLine_last:
		moveq	#1,d4
Seekable_ReverseLine_PutOne:
		add.l	d0,d2
		sub.l	d0,d3
		move.l	d4,-(a7)
		move.l	d3,d4
		bsr	output_buf
Seekable_ReverseLine_PutLoop:
		move.l	d6,d0
		beq	Seekable_ReverseLine_PutDone

		cmp.l	inpbuf_size(a6),d0
		bls	Seekable_ReverseLine_RW

		move.l	inpbuf_size(a6),d0
Seekable_ReverseLine_RW:
		bsr	read
		add.l	d0,d3
		sub.l	d0,d6
		move.l	d0,d4
		bsr	output_buf
		bra	Seekable_ReverseLine_PutLoop

Seekable_ReverseLine_PutDone:
		bsr	check_newline
		move.l	(a7)+,d4
		subq.l	#1,d4
		beq	tail_done_3

		bsr	tail_file_lines_read
		move.l	d3,d0
		bne	Seekable_ReverseLine_continue
tail_done_3:
		rts
****************
tail_RelBot_Unseekable:
		*  バッファに入るだけデータを読む．
		*  バッファが溢れたら，古いデータを 1バイトずつ捨てる．
		movea.l	inpbuf(a6),a1
		move.l	inpbuf_size(a6),d0
		lea	(a1,d0.l),a2
		moveq	#0,d2				*  D2 <- バッファの有効バイト数
read_to_buffer_loop:
		move.l	#1,-(a7)
		pea	charbuf(a6)
		move.w	d1,-(a7)
		DOS	_READ
		lea	10(a7),a7
		tst.l	d0
		bmi	read_fail
		beq	read_to_buffer_eof

		move.b	charbuf(a6),d0
		tst.b	ignore_from_ctrlz(a6)
		beq	read_to_buffer_ctrlz_ok

		cmp.b	#CTRLZ,d0
		beq	read_to_buffer_eof
read_to_buffer_ctrlz_ok:
		tst.b	ignore_from_ctrld(a6)
		beq	read_to_buffer_ctrld_ok

		cmp.b	#CTRLD,d0
		beq	read_to_buffer_eof
read_to_buffer_ctrld_ok:
		move.b	d0,(a1)+
		addq.l	#1,d2
		cmpa.l	a2,a1
		bne	read_to_buffer_loop

		movea.l	inpbuf(a6),a1
		bra	read_to_buffer_loop

read_to_buffer_eof:
		move.l	d2,d0
		move.l	inpbuf_size(a6),d2
		cmp.l	d0,d2
		slo	d3
		blo	read_to_buffer_done

		move.l	d0,d2
		movea.l	inpbuf(a6),a1
read_to_buffer_done:
		tst.l	count(a6)
		beq	tail_done_3

		btst	#FLAG_byte_unit,d5
		bne	tail_RelBot_Unseekable_Byte
****************
tail_RelBot_Unseekable_Line:
		tst.l	d2
		beq	tail_done_3

		movea.l	a1,a2
		move.l	count(a6),d4			*  D4.L : count

		lea	-1(a1,d2.l),a1
		move.l	a1,d0
		sub.l	inpbuf(a6),d0
		cmp.l	inpbuf_size(a6),d0
		blo	tail_RelBot_Unseekable_Line_1

		suba.l	inpbuf_size(a6),a1
tail_RelBot_Unseekable_Line_1:
		btst	#FLAG_reverse,d5
		bne	tail_RelBot_Unseekable_ReverseLine

		cmpi.b	#LF,(a1)
		beq	tail_RelBot_Unseekable_Line_2

		subq.l	#1,d4		*  改行で終了していない最後の半端な行をカウントする
tail_RelBot_Unseekable_Line_2:
		addq.l	#1,a1
		move.l	a1,d0
		sub.l	inpbuf(a6),d0
		bsr	backward_lines
		bne	tail_done_4

		tst.b	d3
		beq	tail_RelBot_Unseekable_Line_3

		movem.l	d0/a1,-(a7)
		move.l	inpbuf(a6),a1
		adda.l	d2,a1
		sub.l	d2,d0
		neg.l	d0
		bsr	backward_lines
		movem.l	(a7)+,d0/a1
		beq	insufficient_memory
		bmi	tail_done_4
tail_RelBot_Unseekable_Line_3:
		suba.l	d0,a1
		move.l	d0,d4
		bra	output_buf
****************
tail_RelBot_Unseekable_ReverseLine:
		bclr	#FLAG_add_newline,d5
		cmpi.b	#LF,(a1)
		beq	Unseekable_RevLine_1

		bset	#FLAG_add_newline,d5
Unseekable_RevLine_1:
		addq.l	#1,a1
		move.l	a1,d0
		sub.l	inpbuf(a6),d0
		move.l	d2,-(a7)
		moveq	#-1,d2
		bsr	put_backward_lines
		move.l	(a7)+,d2
		tst.l	d4
		beq	tail_done_4

		tst.b	d3
		beq	Unseekable_RevLine_last

		move.l	a1,-(a7)
		move.l	inpbuf(a6),a1
		adda.l	d2,a1
		movea.l	a1,a2
		sub.l	d2,d0
		neg.l	d0
		bsr	backward_a_line
		beq	insufficient_memory

		movem.l	d0/d4/a1,-(a7)
		move.l	a2,d4
		sub.l	a1,d4
		bsr	output_buf
		movem.l	(a7)+,d0/d4/a2	* A1->A2
		movea.l	(a7)+,a1
		movem.l	d0/d4/a2,-(a7)
		move.l	d6,d4
		bsr	output_buf
		movem.l	(a7)+,d0/d4/a1	* A2->A1
		bsr	check_newline
		subq.l	#1,d4
		beq	tail_done_4

		moveq	#-1,d2
		bsr	put_backward_lines
		bne	insufficient_memory
tail_done_4:
		rts

Unseekable_RevLine_last:
		move.l	d6,d4
		bra	output_buf
****************
tail_RelBot_Unseekable_Byte:
		cmp.l	count(a6),d2
		bhs	tail_RelBot_Unseekable_Byte_1

		tst.b	d3
		bne	insufficient_memory

		move.l	d2,d4
		bra	tail_RelBot_Unseekable_Byte_2

tail_RelBot_Unseekable_Byte_1:
		adda.l	d2,a1
		move.l	count(a6),d4
		suba.l	d4,a1
tail_RelBot_Unseekable_Byte_2:
		*  A1 : 出力データの先頭アドレス
		*  D4.L : 出力データのバイト数
		move.l	inpbuf(a6),d2
		add.l	inpbuf_size(a6),d2
		sub.l	a1,d2
		cmp.l	d2,d4
		bls	tail_RelBot_Unseekable_Byte_3

		movem.l	d4,-(a7)
		move.l	d2,d4
		bsr	output_buf
		movem.l	(a7)+,d4
		bmi	tail_done_4

		movea.l	inpbuf(a6),a1
		sub.l	d2,d4
tail_RelBot_Unseekable_Byte_3:
*bra	output_buf
****************************************************************
output_buf:
		btst	#FLAG_output_byte_unit,d5
		bne	output_buf_immediately

		btst	#FLAG_C,d5
		beq	output_buf_immediately

		btst	#FLAG_head,d5
		beq	output_buf_putc_loop

		tst.l	head_count(a6)
output_buf_putc_loop2:
		beq	output_buf_return_1
output_buf_putc_loop:
		subq.l	#1,d4
		bcs	output_buf_return_0

		move.b	(a1)+,d0
		cmp.b	#LF,d0
		bne	output_buf_putc

		st	cr_pending(a6)			*  LFの前にCRをはかせるため
output_buf_putc:
		bsr	flush_cr
		cmp.b	#CR,d0
		seq	cr_pending(a6)
		beq	output_buf_putc_loop

		bsr	putc
		btst	#FLAG_head,d5
		beq	output_buf_putc_loop

		cmp.b	#LF,d0
		bne	output_buf_putc_loop

		subq.l	#1,head_count(a6)
		bra	output_buf_putc_loop2

output_buf_immediately:
		bsr	flush_outbuf
		btst	#FLAG_head,d5
		beq	output_buf_immediately_1

		sub.l	d4,head_count(a6)
		bhi	output_buf_immediately_1

		move.l	head_count(a6),d0
		add.l	d4,d0
		bsr	write
output_buf_return_1:
		moveq	#-1,d0
		rts

output_buf_immediately_1:
		move.l	d4,d0
		bsr	write
output_buf_return_0:
		moveq	#0,d0
		rts
*****************************************************************
* write - データを書き出す
*
* CALL
*      A1     先頭アドレス
*      D0.L   バイト数
*
* RETURN
*      D0.L   破壊
*
* DESCRIPTION
*      書き出しがエラーだったらアボートする．
*****************************************************************
write:
		tst.l	d0
		beq	write_return

		move.l	d0,-(a7)
		move.l	a1,-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		beq	write_return
write_fail:
		lea	msg_write_fail(pc),a0
		bsr	werror
		bra	exit_3
*****************************************************************
tail_file_lines_read:
		move.l	#READSIZE,d0
		cmp.l	d2,d0
		bls	tail_file_lines_read_1

		move.l	d2,d0
tail_file_lines_read_1:
		move.l	d0,-(a7)
		add.l	d3,d0
		neg.l	d0
		bsr	seek_relative
		bmi	seek_fail

		move.l	d0,d2
		move.l	(a7)+,d0
		move.l	d0,d3
		beq	tail_file_lines_read_2

		bsr	read
		cmp.l	d3,d0
		bne	read_fail
tail_file_lines_read_2:
		movea.l	inpbuf(a6),a1
		adda.l	d3,a1
		tst.l	d3
write_return:
		rts
*****************************************************************
backward_lines:
		movem.l	d0,-(a7)
		move.l	a1,-(a7)
backward_lines_loop:
		bsr	backward_a_line
		beq	backward_lines_return		*  Z

		subq.l	#1,d4
		bcs	backward_lines_complete

		subq.l	#1,d0
		subq.l	#1,a1
		bra	backward_lines_loop

backward_lines_complete:
		move.l	(a7),d4
		sub.l	a1,d4
		bsr	output_buf
		bmi	backward_lines_return		*  NZ, MI

		moveq	#1,d0				*  NZ, PL
backward_lines_return:
		movea.l	(a7)+,a1
		movem.l	(a7)+,d0			*  Do not change condition code
		rts
*****************************************************************
* backward_a_line - データをケツから頭に向かってスキャンして改行を探す
*
* CALL
*      A1     データの末尾+1
*      D0.L   データのバイト数
*
* RETURN
*      A1     改行があれば，その改行の直後を指す．
*             改行が無ければデータの先頭を指す．
*      D0.L   改行があれば，その改行以前に残っているバイト数．
*             改行が無ければ 0．
*      CCR    ADDQ.L #1,D0
*****************************************************************
backward_a_line:
backward_a_line_loop:
		subq.l	#1,d0
		bcs	backward_a_line_return

		cmpi.b	#LF,-(a1)
		bne	backward_a_line_loop

		addq.l	#1,a1
backward_a_line_return:
		addq.l	#1,d0
		rts
****************************************************************
put_backward_lines:
		movea.l	a1,a2
		btst	#FLAG_add_newline,d5
		bne	put_backward_lines_loop
put_backward_lines_continue:
		movea.l	a1,a2
		subq.l	#1,a1
		subq.l	#1,d0
put_backward_lines_loop:
		bsr	backward_a_line
		move.l	a2,d6
		sub.l	a1,d6
		tst.l	d0
		bne	put_backward_lines_PutOne

		tst.l	d2
		bne	put_backward_lines_return

		moveq	#1,d4
put_backward_lines_PutOne:
		movem.l	d0/d4/a1,-(a7)
		move.l	d6,d4
		bsr	output_buf
		movem.l	(a7)+,d0/d4/a1
		bsr	check_newline
		subq.l	#1,d4
		bne	put_backward_lines_continue
put_backward_lines_return:
		rts
*****************************************************************
putc:
		tst.b	do_buffering(a6)
		bne	putc_do_buffering

		move.l	d0,-(a7)

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail

		move.l	(a7)+,d0
		bra	putc_done

putc_do_buffering:
		tst.l	outbuf_free(a6)
		bne	putc_do_buffering_1

		bsr	flush_outbuf
putc_do_buffering_1:
		move.b	d0,(a5)+
		subq.l	#1,outbuf_free(a6)
putc_done:
		rts
*****************************************************************
check_newline:
		btst	#FLAG_add_newline,d5
		beq	check_newline_ok

		bclr	#FLAG_add_newline,d5
put_newline:
		move.l	d0,-(a7)
		moveq	#CR,d0
		bsr	putc
		moveq	#LF,d0
		bsr	putc
		move.l	(a7)+,d0
check_newline_ok:
		rts
*****************************************************************
puts:
		movem.l	d0/a0,-(a7)
puts_loop:
		move.b	(a0)+,d0
		beq	puts_done

		bsr	putc
		bra	puts_loop
puts_done:
		movem.l	(a7)+,d0/a0
read_return:
		rts
*****************************************************************
* read - inpbuf にデータを読み込む
*
* CALL
*      D0.L   読み込むバイト数．READSIZE以下であること．
*      D1.W   ファイル・ハンドル
*
* RETURN
*      D0.L   読み込んだバイト数
*      A1     inpbuf
*      CCR    TST.L D0
*
* DESCRIPTION
*      D0.L バイトを限度に読み込む．
*      読み込みがエラーだったらアボートする．
*****************************************************************
read:
		movea.l	inpbuf(a6),a1
		move.l	d0,-(a7)
		move.l	a1,-(a7)
		move.w	d1,-(a7)
		DOS	_READ
		lea	10(a7),a7
		tst.l	d0
		bpl	read_return
read_fail:
seek_fail:
		bsr	flush_outbuf
		lea	msg_read_fail(pc),a2
werror_exit_2:
		bsr	werror_myname_and_msg
		movea.l	a2,a0
		bsr	werror
		moveq	#2,d6
		bra	exit_program
*****************************************************************
* read_some - inpbuf にデータを読み込む
*
* CALL
*      D1.W   ファイル・ハンドル
*
* RETURN
*      D0.L   読み込んだバイト数
*      D4.L   切り詰め後のバイト数
*      A1     inpbuf
*      CCR    TST.L D4
*
* DESCRIPTION
*      READSIZE バイトを限度に読み込み，truncする．
*      読み込みがエラーだったらアボートする．
*****************************************************************
read_some:
		move.l	#READSIZE,d0
		bsr	read
		move.l	d0,d4
		movem.l	d1-d2/a0,-(a7)
		tst.b	ignore_from_ctrlz(a6)
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d1
		bsr	trunc
trunc_ctrlz_done:
		tst.b	ignore_from_ctrld(a6)
		beq	trunc_ctrld_done

		moveq	#CTRLD,d1
		bsr	trunc
trunc_ctrld_done:
		movem.l	(a7)+,d1-d2/a0
		tst.l	d4
		rts

trunc:
		movea.l	a1,a0
		move.l	d4,d2
trunc_find_loop:
		subq.l	#1,d2
		bcs	trunc_return

		cmp.b	(a0)+,d1
		bne	trunc_find_loop

		subq.l	#1,a0
		move.l	a0,d4
		sub.l	a1,d4
		bset	#FLAG_eof,d5
trunc_return:
		rts
*****************************************************************
* seek_to_phigical_eof - 物理的なファイルの終わりにシークする
*
* CALL
*      D1.W   ファイル・ハンドル
*
* RETURN
*      D0.L   先頭からのオフセット
*             負ならばOSのエラーコード
*      CCR    TST.L D0
*****************************************************************
seek_to_phigical_eof:
		move.w	#2,-(a7)
seeksub0:
		moveq	#0,d0
seeksub:
		move.l	d0,-(a7)
		move.w	d1,-(a7)
		DOS	_SEEK
		addq.l	#8,a7
		tst.l	d0
		rts
*****************************************************************
* seek_relative - 相対的にシークする
*
* CALL
*      D0.L   現在位置に対するオフセット
*      D1.W   ファイル・ハンドル
*
* RETURN
*      D0.L   先頭からのオフセット
*             負ならばOSのエラーコード
*      CCR    TST.L D0
*****************************************************************
seek_relative:
		move.w	#1,-(a7)
		bra	seeksub
*****************************************************************
* seek_from_top - 絶対位置にシークする
*
* CALL
*      D0.L   シーク位置（先頭からのオフセット）
*      D1.W   ファイル・ハンドル
*
* RETURN
*      D0.L   先頭からのオフセット
*             負ならばOSのエラーコード
*      CCR    TST.L D0
*****************************************************************
seek_from_top:
		clr.w	-(a7)
		bra	seeksub
*****************************************************************
* check_input_device - 入力デバイスをチェックする
*
* CALL
*      D1.W   ファイル・ハンドル
*
* RETURN
*      D0.L   破壊
*****************************************************************
check_input_device:
		btst	#FLAG_Z,d5
		sne	ignore_from_ctrlz(a6)
		sf	ignore_from_ctrld(a6)
		move.w	d1,d0
		bsr	is_chrdev
		beq	check_input_device_seekable	*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	check_input_device_seekable

		st	ignore_from_ctrlz(a6)
		st	ignore_from_ctrld(a6)
check_input_device_seekable:
		bset	#FLAG_can_seek,d5
		moveq	#1,d0
		bsr	seek_from_top
		cmp.l	#1,d0
		beq	check_input_device_seekable_1

		bclr	#FLAG_can_seek,d5
check_input_device_seekable_1:
		moveq	#0,d0
		bsr	seek_from_top
		beq	check_input_device_seekable_2

		bclr	#FLAG_can_seek,d5
check_input_device_seekable_2:
		rts
*****************************************************************
is_chrdev:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
insufficient_memory:
		lea	msg_no_memory(pc),a0
		bsr	werror_myname_and_msg
exit_3:
		moveq	#3,d6
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## tail 1.2 ##  Copyright(C)1993-94 by Itagaki Fumihiko',0

msg_myname:		dc.b	'tail: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_open_fail:		dc.b	': オープンできません',CR,LF,0
msg_read_fail:		dc.b	': 入力エラー',CR,LF,0
msg_write_fail:		dc.b	'tail: 出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_illegal_count:	dc.b	'カウントの指定が不正です',0
msg_header1:		dc.b	CR,LF
msg_header2:		dc.b	'==> ',0
msg_header3:		dc.b	' <=='
msg_newline:		dc.b	CR,LF,0
msg_usage:		dc.b	CR,LF,'使用法:  tail [-qvBCZ] { [ {-+}<#>[ckl][-<#>[ckl]] | -[<#>]r ] [--] [<ファイル>] } ...',CR,LF,0
*****************************************************************
offset 0
stdin:			ds.l	1
inpbuf:			ds.l	1
inpbuf_size:		ds.l	1
outbuf_free:		ds.l	1
count:			ds.l	1
head_count:		ds.l	1
show_header:		ds.b	1
ignore_from_ctrlz:	ds.b	1
ignore_from_ctrld:	ds.b	1
do_buffering:		ds.b	1
charbuf:		ds.b	1
cr_pending:		ds.b	1
.even
			ds.b	STACKSIZE
.even
stack_bottom:

.bss
.even
bss_top:
		ds.b	stack_bottom
*****************************************************************

.end start
