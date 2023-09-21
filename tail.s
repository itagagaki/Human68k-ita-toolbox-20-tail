* tail - output tail of input
*
* Itagaki Fumihiko 07-Feb-93  Create.
* 1.0
*
* Usage: tail [ -qvBCZ ] { [ [{+-}<N>[ckl]] [-[<N>]r] [ -- ] [ <ファイル> ] } ...

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref isdigit
.xref atou
.xref strlen
.xref strfor1
.xref strip_excessive_slashes

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
FLAG_reverse		equ	7
FLAG_add_newline	equ	8

.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom(pc),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
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
		move.l	#DEFAULT_COUNT,count
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
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering
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
		move.l	d0,outbuf_free
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a4				*  A4 : 出力バッファの先頭アドレス
		movea.l	d0,a5				*  A5 : 出力バッファのポインタ
outbuf_ok:
		bsr	parse_count
		lea	msg_header2(pc),a1
		st	show_header
		btst	#FLAG_v,d5
		bne	do_files

		sf	show_header
		btst	#FLAG_q,d5
		bne	do_files

		cmp.l	#1,d7
		shi	show_header
do_files:
	*
	*  入力バッファを確保する
	*
		move.l	#$00ffffff,d0
		move.l	d0,inpbufsize
		bsr	malloc
		bpl	inpbuf_ok

		sub.l	#$81000000,d0
		cmp.l	#READSIZE,d0
		blt	insufficient_memory

		move.l	d0,inpbufsize
		bsr	malloc
		blt	insufficient_memory
inpbuf_ok:
		move.l	d0,inpbuf
	*
	*  開始
	*
		tst.l	d7
		beq	no_file_arg
for_file_loop:
		movea.l	a0,a3
		bsr	strfor1
		exg	a0,a3
		cmpi.b	#'-',(a0)
		bne	for_file_1

		tst.b	1(a0)
		bne	for_file_1

		bsr	do_stdin
		bra	for_file_continue

for_file_1:
		bsr	strip_excessive_slashes
		lea	msg_open_fail(pc),a2
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
		tst.l	d0
		bmi	werror_exit_2

		move.w	d0,d1
		bsr	dofile
		move.w	d1,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
for_file_continue:
		movea.l	a3,a0
		subq.l	#1,d7
		bsr	parse_count
		tst.l	d7
		beq	all_done

		lea	msg_header1(pc),a1
		bra	for_file_loop

no_file_arg:
		bsr	do_stdin
all_done:
		moveq	#0,d0
exit_program:
		move.w	d0,-(a7)
		DOS	_EXIT2
****************************************************************
parse_count:
parse_count_loop:
		tst.l	d7
		beq	parse_count_done

		cmpi.b	#'+',(a0)
		beq	parse_count_1

		cmpi.b	#'-',(a0)
		bne	parse_count_done

		cmpi.b	#'r',1(a0)
		bne	parse_count_1

		tst.b	2(a0)
		bne	parse_count_break

		moveq	#-1,d1
		addq.l	#1,a0
		bra	parse_count_3

parse_count_1:
		move.b	1(a0),d0
		bsr	isdigit
		bne	parse_count_break

		bclr	#FLAG_from_top,d5
		cmpi.b	#'-',(a0)
		beq	parse_count_2

		bset	#FLAG_from_top,d5
parse_count_2:
		addq.l	#1,a0
		bsr	atou
		bne	bad_count
parse_count_3:
		move.l	d1,count
		subq.l	#1,d7
		bclr	#FLAG_byte_unit,d5
		bclr	#FLAG_reverse,d5
		move.b	(a0),d0
		beq	parse_count_continue

		cmp.b	#'l',d0
		beq	parse_count_unit_ok

		btst	#FLAG_from_top,d5
		bne	parse_count_4

		bset	#FLAG_reverse,d5
		cmp.b	#'r',d0
		beq	parse_count_unit_ok
parse_count_4:
		bset	#FLAG_byte_unit,d5
		cmp.b	#'c',d0
		beq	parse_count_unit_ok

		cmp.b	#'k',d0
		bne	bad_count

		cmp.l	#$400000,d1
		bhs	bad_count

		lsl.l	#8,d1
		lsl.l	#2,d1
		move.l	d1,count
parse_count_unit_ok:
		addq.l	#1,a0
parse_count_continue:
		tst.b	(a0)+
		beq	parse_count_loop
bad_count:
		lea	msg_illegal_count(pc),a0
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d0
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
* dofile
****************************************************************
do_stdin:
		lea	msg_stdin(pc),a0
		moveq	#0,d1
dofile:
		sf	cr_pending
		tst.b	show_header
		beq	dofile1

		move.l	a0,-(a7)
		movea.l	a1,a0
		bsr	puts
		movea.l	(a7),a0
		bsr	puts
		lea	msg_header3(pc),a0
		bsr	puts
		movea.l	(a7)+,a0
dofile1:
		bsr	check_input_device
		bsr	dofile2
		bsr	flush_cr
flush_outbuf:
		move.l	d0,-(a7)
		tst.b	do_buffering
		beq	flush_done

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free,d0
		beq	flush_done

		exg	a1,a4
		bsr	write
		exg	a1,a4
		movea.l	a4,a5
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
flush_done:
		move.l	(a7)+,d0
output_remainder_return:
		rts

flush_cr:
		tst.b	cr_pending
		beq	flush_cr_return

		move.l	d0,-(a7)
		moveq	#CR,d0
		bsr	putc
		move.l	(a7)+,d0
flush_cr_return:
		rts
****************
dofile2:
		btst	#FLAG_from_top,d5
		beq	tail_FromBot
****************
tail_FromTop:
		move.l	count,d2			*  D2.L : カウント
		beq	output_remainder_ReadThenOutput
		*
		*  count行読みとばす
		*
		sf	eof_detected
skip_head_loop:
		tst.b	eof_detected
		bne	dofile1_done

		bsr	read_some
		bsr	trunc				*  D4.L := 有効バイト数
		beq	dofile1_done

		movea.l	inpbuf,a1
		btst	#FLAG_byte_unit,d5
		bne	skip_head_byte
skip_head_line_loop:
		move.b	(a1)+,d0
		subq.l	#1,d4
		cmp.b	#LF,d0
		bne	skip_head_line_continue

		subq.l	#1,d2
		beq	skip_head_done
skip_head_line_continue:
		tst.l	d4
		bne	skip_head_line_loop
		bra	skip_head_loop

skip_head_byte:
		sub.l	d4,d2
		bhi	skip_head_loop

		neg.l	d2
		adda.l	d4,a1
		move.l	d2,d4
		suba.l	d4,a1
skip_head_done:
		bra	output_remainder_OutputThenRead
****************
tail_FromBot:
		tst.l	count
		beq	dofile1_done

		tst.b	input_is_block
		beq	tail_FromBot_Unseekable
****************
tail_FromBot_Seekable:
		*
		*  論理的なファイルの終わりにシークする
		*
		tst.b	ignore_from_ctrlz
		bne	seek_to_logical_eof_1

		tst.b	ignore_from_ctrld
		bne	seek_to_logical_eof_1

		bsr	seek_to_phigical_eof
		bra	seek_to_logical_eof_done

seek_to_logical_eof_1:
		sf	eof_detected
seek_to_logical_eof_loop:
		bsr	read_some
		beq	seek_to_logical_eof_2		*  D0.L == 0

		move.l	d0,d2				*  D2.L := 読み込んだバイト数
		bsr	trunc
		tst.b	eof_detected
		beq	seek_to_logical_eof_loop

		*  EOF以降読み進んでしまった分戻る
		move.l	d4,d0
		sub.l	d2,d0
seek_to_logical_eof_2:
		bsr	seek_relative
seek_to_logical_eof_done:
		bmi	seek_fail

		st	eof_detected

		*  ここで，D0.L : 現在の位置

		btst	#FLAG_byte_unit,d5
		bne	tail_FromBot_Seekable_Byte
****************
tail_FromBot_Seekable_Line:
		move.l	d0,d2				*  D2.L : 現在の位置
		moveq	#0,d3				*  D3.L : 先走り量
		move.l	count,d4			*  D4.L : count
		bsr	tail_file_lines_read
		beq	dofile1_done

		btst	#FLAG_reverse,d5
		bne	tail_FromBot_Seekable_ReverseLine

		cmpi.b	#LF,-1(a1)
		beq	tail_FromBot_Seekable_Line_1

		subq.l	#1,d4		*  改行で終了していない最後の半端な行をカウントする
tail_FromBot_Seekable_Line_1:
		move.l	d3,d0
		bsr	backward_lines
		bne	dofile1_done			*  この先にはもう無い
tail_FromBot_Seekable_Line_loop:
		bsr	tail_file_lines_read
		beq	output_remainder_ReadThenOutput

		move.l	d3,d0
		bsr	backward_lines
		bne	output_remainder_ReadThenOutput
		bra	tail_FromBot_Seekable_Line_loop

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
		movea.l	inpbuf,a1
		adda.l	d3,a1
		tst.l	d3
		rts
****************
tail_FromBot_Seekable_ReverseLine:
		move.l	d3,d0
		bset	#FLAG_add_newline,d5
		cmpi.b	#LF,-1(a1)
		bne	Seekable_ReverseLine_1
Seekable_ReverseLine_continue:
		bclr	#FLAG_add_newline,d5
Seekable_ReverseLine_1:
		bsr	put_backward_lines
		beq	dofile1_done
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
		bsr	output_remainder_OutputThenRead
Seekable_ReverseLine_PutLoop:
		move.l	d6,d0
		beq	Seekable_ReverseLine_PutDone

		cmp.l	inpbufsize,d0
		bls	Seekable_ReverseLine_RW

		move.l	inpbufsize,d0
Seekable_ReverseLine_RW:
		bsr	read
		add.l	d0,d3
		sub.l	d0,d6
		movea.l	inpbuf,a1
		move.l	d0,d4
		bsr	output_remainder_OutputThenRead
		bra	Seekable_ReverseLine_PutLoop

Seekable_ReverseLine_PutDone:
		bsr	check_newline
		move.l	(a7)+,d4
		subq.l	#1,d4
		beq	dofile1_done

		bsr	tail_file_lines_read
		move.l	d3,d0
		beq	dofile1_done

		bra	Seekable_ReverseLine_continue
****************
tail_FromBot_Seekable_Byte:
		cmp.l	count,d0
		bls	tail_FromBot_Seekable_Byte_1

		move.l	count,d0
tail_FromBot_Seekable_Byte_1:
		neg.l	d0
		bsr	seek_relative
		bmi	seek_fail

		bra	output_remainder_ReadThenOutput
****************
tail_FromBot_Unseekable:
		*  バッファに入るだけデータを読む．
		*  バッファが溢れたら，古いデータを 1バイトずつ捨てる．
		movea.l	inpbuf,a1
		move.l	inpbufsize,d0
		lea	(a1,d0.l),a2
		moveq	#0,d2				*  D2 <- バッファの有効バイト数
read_to_buffer_loop:
		move.l	#1,-(a7)
		pea	charbuf(pc)
		move.w	d1,-(a7)
		DOS	_READ
		lea	10(a7),a7
		tst.l	d0
		bmi	read_fail
		beq	read_to_buffer_eof

		move.b	charbuf,d0
		tst.b	ignore_from_ctrlz
		beq	read_to_buffer_ctrlz_ok

		cmp.b	#CTRLZ,d0
		beq	read_to_buffer_eof
read_to_buffer_ctrlz_ok:
		tst.b	ignore_from_ctrld
		beq	read_to_buffer_ctrlz_ok

		cmp.b	#CTRLD,d0
		beq	read_to_buffer_eof
read_to_buffer_ctrld_ok:
		move.b	d0,(a1)+
		addq.l	#1,d2
		cmpa.l	a2,a1
		bne	read_to_buffer_loop

		movea.l	inpbuf,a1
		bra	read_to_buffer_loop

read_to_buffer_eof:
		move.l	d2,d0
		move.l	inpbufsize,d2
		cmp.l	d0,d2
		slo	d3
		blo	read_to_buffer_done

		move.l	d0,d2
		movea.l	inpbuf,a1
read_to_buffer_done:
		st	eof_detected

		btst	#FLAG_byte_unit,d5
		bne	tail_FromBot_Unseekable_Byte
****************
tail_FromBot_Unseekable_Line:
		tst.l	d2
		beq	dofile1_done

		movea.l	a1,a2
		move.l	count,d4			*  D4.L : count

		lea	-1(a1,d2.l),a1
		move.l	a1,d0
		sub.l	inpbuf,d0
		cmp.l	inpbufsize,d0
		blo	tail_FromBot_Unseekable_Line_1

		suba.l	inpbufsize,a1
tail_FromBot_Unseekable_Line_1:
		btst	#FLAG_reverse,d5
		bne	tail_FromBot_Unseekable_ReverseLine

		cmpi.b	#LF,(a1)
		beq	tail_FromBot_Unseekable_Line_2

		subq.l	#1,d4		*  改行で終了していない最後の半端な行をカウントする
tail_FromBot_Unseekable_Line_2:
		addq.l	#1,a1
		move.l	a1,d0
		sub.l	inpbuf,d0
		bsr	backward_lines
		bne	dofile1_done

		tst.b	d3
		beq	tail_FromBot_Unseekable_Line_3

		movem.l	d0/a1,-(a7)
		move.l	inpbuf,a1
		adda.l	d2,a1
		sub.l	d2,d0
		neg.l	d0
		bsr	backward_lines
		movem.l	(a7)+,d0/a1
		beq	insufficient_memory
tail_FromBot_Unseekable_Line_3:
		move.l	d0,d4
		bra	output_remainder_OutputThenRead
****************
tail_FromBot_Unseekable_ReverseLine:
		bclr	#FLAG_add_newline,d5
		cmpi.b	#LF,(a1)
		beq	Unseekable_RevLine_1

		bset	#FLAG_add_newline,d5
Unseekable_RevLine_1:
		addq.l	#1,a1
		move.l	a1,d0
		sub.l	inpbuf,d0
		move.l	d2,-(a7)
		moveq	#-1,d2
		bsr	put_backward_lines
		move.l	(a7)+,d2
		tst.l	d4
		beq	dofile1_done

		tst.b	d3
		beq	Unseekable_RevLine_last

		move.l	a1,-(a7)
		move.l	inpbuf,a1
		adda.l	d2,a1
		movea.l	a1,a2
		sub.l	d2,d0
		neg.l	d0
		bsr	backward_a_line
		beq	insufficient_memory

		movem.l	d0/d4/a1,-(a7)
		move.l	a2,d4
		sub.l	a1,d4
		bsr	output_remainder_OutputThenRead
		movem.l	(a7)+,d0/d4/a2	* A1->A2
		movea.l	(a7)+,a1
		movem.l	d0/d4/a2,-(a7)
		move.l	d6,d4
		bsr	output_remainder_OutputThenRead
		movem.l	(a7)+,d0/d4/a1	* A2->A1
		bsr	check_newline
		subq.l	#1,d4
		beq	dofile1_done

		moveq	#-1,d2
		bsr	put_backward_lines
		beq	dofile1_done
		bra	insufficient_memory

Unseekable_RevLine_last:
		move.l	d6,d4
		bra	output_remainder_OutputThenRead
****************
tail_FromBot_Unseekable_Byte:
		cmp.l	count,d2
		bhs	tail_FromBot_Unseekable_Byte_1

		tst.b	d3
		bne	insufficient_memory

		move.l	d2,d4
		bra	tail_FromBot_Unseekable_Byte_2

tail_FromBot_Unseekable_Byte_1:
		adda.l	d2,a1
		move.l	count,d4
		suba.l	d4,a1
tail_FromBot_Unseekable_Byte_2:
		*  A1 : 出力データの先頭アドレス
		*  D4.L : 出力データのバイト数
		bsr	flush_outbuf
		move.l	inpbuf,d2
		add.l	inpbufsize,d2
		sub.l	a1,d2
		cmp.l	d4,d2
		bls	tail_FromBot_Unseekable_Byte_3

		move.l	d4,d2
tail_FromBot_Unseekable_Byte_3:
		move.l	d2,d0
		bsr	write
		sub.l	d2,d4
		bls	tail_FromBot_Unseekable_Byte_4

		movea.l	inpbuf,a1
		move.l	d4,d0
		bsr	write
tail_FromBot_Unseekable_Byte_4:
dofile1_done:
		rts
*****************************************************************
backward_lines:
		movem.l	d0,-(a7)
		move.l	a1,-(a7)
backward_lines_loop:
		bsr	backward_a_line
		beq	backward_lines_return		*  ZF == 1

		subq.l	#1,d4
		bcs	backward_lines_complete

		subq.l	#1,d0
		subq.l	#1,a1
		bra	backward_lines_loop

backward_lines_complete:
		move.l	(a7),d4
		sub.l	a1,d4
		bsr	output_remainder_OutputThenRead
		moveq	#-1,d0				*  ZF <- 0
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
		bsr	output_remainder_OutputThenRead
		movem.l	(a7)+,d0/d4/a1
		bsr	check_newline
		subq.l	#1,d4
		bne	put_backward_lines_continue
put_backward_lines_return:
		rts
****************************************************************
output_remainder_ReadThenOutput:
		sf	eof_detected
output_remainder_loop:
		tst.b	eof_detected
		bne	output_remainder_return

		bsr	read_some
		bsr	trunc				*  D4.L := 有効バイト数
		beq	output_remainder_return

		movea.l	inpbuf,a1
output_remainder_OutputThenRead:
		tst.l	d4
		beq	output_remainder_loop

		btst	#FLAG_byte_unit,d5
		bne	output_remainder_immediately

		btst	#FLAG_C,d5
		beq	output_remainder_immediately
output_remainder_putc_loop:
		move.b	(a1)+,d0
		cmp.b	#LF,d0
		bne	output_remainder_putc

		st	cr_pending			*  LFの前にCRをはかせるため
output_remainder_putc:
		bsr	flush_cr
		cmp.b	#CR,d0
		seq	cr_pending
		beq	output_remainder_putc_continue

		bsr	putc
output_remainder_putc_continue:
		subq.l	#1,d4
		bne	output_remainder_putc_loop
		bra	output_remainder_loop

output_remainder_immediately:
		bsr	flush_outbuf
		move.l	d4,d0
		bsr	write
		bra	output_remainder_loop
*****************************************************************
putc:
		tst.b	do_buffering
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
		tst.l	outbuf_free
		bne	putc_do_buffering_1

		bsr	flush_outbuf
putc_do_buffering_1:
		move.b	d0,(a5)+
		subq.l	#1,outbuf_free
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
write_return:
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
* read, read_some - inpbuf にデータを読み込む
*
* CALL
*      D0.L   読み込むバイト数．READSIZE以下であること．（read）
*      D1.W   ファイル・ハンドル
*
* RETURN
*      D0.L   読み込んだバイト数
*      D4.L   読み込んだバイト数（read_some）
*      CCR    TST.L D0
*
* DESCRIPTION
*      read では，D0.L < READSIZE ならば D0.L バイトを限度に読み
*      込み，そうでなければ READSIZE バイトを限度に読み込む．
*
*      read_some では READSIZE バイトを限度に読み込む．
*
*      読み込みがエラーだったらアボートする．
*****************************************************************
read_some:
		move.l	#READSIZE,d0
		bsr	read
		move.l	d0,d4
read_return:
		rts

read:
		move.l	d0,-(a7)
		move.l	inpbuf,-(a7)
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
		moveq	#2,d0
		bra	exit_program
*****************************************************************
* trunc - inpbuf をスキャンし，EOF があったら切り詰める．
*
* CALL
*      (inpbuf)   読み込んだデータ
*      D4.L   読み込んだバイト数
*
* RETURN
*      D3.L   bit0 : 切り詰めたときセットされる
*      D4.L   切り詰めたバイト数
*      CCR    TST.L D4
*****************************************************************
trunc:
		tst.b	ignore_from_ctrlz
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc_sub
trunc_ctrlz_done:
		tst.b	ignore_from_ctrld
		beq	trunc_return

		moveq	#CTRLD,d0
trunc_sub:
		tst.l	d4
		beq	trunc_return

		movem.l	d1/a0,-(a7)
		movea.l	inpbuf,a0
		move.l	d4,d1
trunc_find_loop:
		cmp.b	(a0)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
		bra	trunc_done

trunc_found:
		subq.l	#1,a0
		move.l	a0,d4
		movea.l	inpbuf,a0
		sub.l	a0,d4
		st	eof_detected
trunc_done:
		movem.l	(a7)+,d1/a0
trunc_return:
		tst.l	d4
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
*****************************************************************
seek_relative:
		move.w	#1,-(a7)
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
		sne	ignore_from_ctrlz
		sf	ignore_from_ctrld
		move.w	d1,d0
		bsr	is_chrdev
		seq	input_is_block
		beq	check_input_device_done		*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	check_input_device_done

		st	ignore_from_ctrlz
		st	ignore_from_ctrld
check_input_device_done:
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
		moveq	#3,d0
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
	dc.b	'## tail 1.0 ##  Copyright(C)1993 by Itagaki Fumihiko',0

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
msg_usage:		dc.b	CR,LF,'使用法:  tail [-qvBCZ] { [{-+}<N>[ckl]] [-[<N>]r] [--] [<ファイル>] } ...',CR,LF,0
*****************************************************************
.bss

.even
outbuf_free:		ds.l	1
count:			ds.l	1
eofpos:			ds.l	1
inpbuf:			ds.l	1
inpbufsize:		ds.l	1
show_header:		ds.b	1
input_is_block:		ds.b	1
ignore_from_ctrlz:	ds.b	1
ignore_from_ctrld:	ds.b	1
do_buffering:		ds.b	1
charbuf:		ds.b	1
eof_detected:		ds.b	1
cr_pending:		ds.b	1

		ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
