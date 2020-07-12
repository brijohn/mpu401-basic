/*
 * The code used to extend basic's tokenize, detokenize, and execute
 * functions was taken from the Mega65 project.
 * Github: https://github.com/MEGA65
 *         https://github.com/MEGA65/mega-basic64
 *
 * This was modified to work with kick assembler and support my own
 * set of extended tokens.
 */

/* Works on modified version of the ROM tokeniser, but with extended
 * token list.
 * Original C64 ROM routine is from $A57C to $A612.
 * The BASIC keyword list is at $A09E to $A19F.
 * $A5BC is the part that reads a byte from the token list.
 * The main complication is that the token list is already $FF bytes
 * long, so we can't extend it an keep using an 8-bit offset.
 * We can replace the SBC $A09E,Y with a JSR to a new routine that can
 * handle >256 bytes of token list.  But life is not that easy, either,
 * because Y is used in all sorts of other places in that routine.
 *
 *
 * We will need two pages of tokens, so $A5AE needs to reset access to the low-page
 * of tokens, as well as Y=0, $0B=0
 */

.var tokens = Hashtable()
.var token_count = 0
.var token_first_sub_command = $cc
.macro OutputToken(token, end_of_main_token_list) {
	.eval tokens.put(token.toLowerCase(), $CC + token_count)
	.for(var i=0;i<token.size();i++) {
		.if (i == token.size() - 1) {
			.byte token.charAt(i) + $80
		} else {
			.byte token.charAt(i)
		}
	}
	.eval token_count+=1
	.if (end_of_main_token_list != 0) {
		.eval token_first_sub_command+=token_count
	}
//	.print token + ": " + toHexString(tokens.get(token.toLowerCase()))
}

.const tokenise_vector   = $0304
.const untokenise_vector = $0306
.const execute_vector    = $0308

.align $100
.memblock "Basic Token List"
tokenlist:
	.fill ($A19C - $A09E + 1), $00
	:OutputToken("MPU", 0)
	:OutputToken("MIDI", 1)
	:OutputToken("VOICE", 0)
	:OutputToken("PROGRAM", 0)
	:OutputToken("CTRL", 0)
	:OutputToken("PITCH", 0)
	:OutputToken("OFF", 0)
	:OutputToken("IN", 0)
	.byte 00

.align $100
.memblock "MPU401 Basic Extensions"
mpu_tokenize: {
	// Get the basic execute pointer low byte
	ldx $7A
	// Set the save index
	ldy #$04
	// Clear the quote/data flag
	sty $0F

tokeniseNextChar:
	/* Get hi page flag for tokenlist scanning, so that if we INC it, it will
	 * point back to the first page.  As we start with offset = $FF, the first
	 * increment will do this. Since offsets are pre-incremented, this means
	 * that it will switch to the low page at the outset, and won't switch again
	 * until a full page has been stepped through.
     */
	pha
	lda #$FF
	sta token_hi_page_flag
	pla

	// Read a byte from the input buffer
	lda $0200,X
	// If bit 7 is clear, try to tokenise
	bpl tryTokenise
	// Now check for PI (char $FF)
	cmp #$FF               // = PI
	beq gotToken_a5c9
	// Not PI, but bit 7 is set, so just skip over it, and don't store
	inx
	bne tokeniseNextChar
tryTokenise:
	// Now look for some common things
	// Is it a space?
	cmp #$20               // space
	beq gotToken_a5c9
	// Not space, so save byte as search character
	sta $08
	cmp #$22               // quote marks
	beq foundQuotes_a5ee
	bit $0F                // Check quote/data mode
	bvs gotToken_a5c9     // If data mode, accept as is
	cmp #$3F               // Is it a "?" (short cut for PRINT)
	bne notQuestionMark
	lda #$99               // Token for PRINT
	bne gotToken_a5c9     // Accept the print token (branch always taken, because $99 != $00)
notQuestionMark:
	// Check for 0-9, : or ;
	cmp #$30
	bcc notADigit
	cmp #$3C
	bcc gotToken_a5c9
notADigit:
	// Remember where we are upto in the BASIC line of text
	sty $71
	// Now reset the pointer into tokenlist
	ldy #$00
	// And the token number minus $80 we are currently considering.
	// We start with token #0, since we search from the beginning.
	sty $0B
	// Decrement Y from $00 to $FF, because the inner loop increments before processing
	// (Y here represents the offset in the tokenlist)
	dey
	// Save BASIC execute pointer
	stx	$7A
	// Decrement X also, because the inner loop pre-increments
	dex
compareNextChar_a5b6:
	// Advance pointer in tokenlist
	jsr tokenListAdvancePointer
	// Advance pointer in BASIC text
	inx
compareProgramTextAndToken:
	// Read byte of basic program
	lda $0200,x
	// Now subtract the byte from the token list.
	// If the character matches, we will get $00 as result.
	// If the character matches, but was ORd with $80, then $80 will be the
	// result.  This allows efficient detection of whether we have found the
	// end of a keyword.
	bit token_hi_page_flag
	bmi useTokenListHighPage
	sec
	sbc tokenlist,y
	jmp dontUseHighPage
useTokenListHighPage:
	sec
	sbc tokenlist+$100,y
dontUseHighPage:
	// If zero, then compare the next character
	beq compareNextChar_a5b6
	// If $80, then it is the end of the token, and we have matched the token
	cmp #$80
	bne tokenDoesntMatch
	// A = $80, so if we add the token number stored in $0B, we get the actual
	// token number
	ora $0B
tokeniseNextProgramCharacter:
	// Restore the saved index into the BASIC program line
	ldy $71
gotToken_a5c9:
	// We have worked out the token, so record it.
	inx
	iny
	sta $0200 - 5,y
	// Now check for end of line (token == $00)
	lda $0200 - 5,y
	beq tokeniseEndOfLine_a609

	// Now think about what we have to do with the token
	sec
	sbc #$3A
	beq tokenIsColon_a5dc
	cmp #($83 - $3A)                // (=$49) Was it the token for DATA?
	bne tokenMightBeREM_a5de
tokenIsColon_a5dc:
	// Token was DATA
	sta $0F                         // Store token - $3A (why?)
tokenMightBeREM_a5de:
	sec
	sbc #($8F - $3A)                // (=$55) Was it the token for REM?
	bne tokeniseNextChar
	// Was REM, so say we are searching for end of line (== $00)
	// (which is conveniently in A now)
	sta $08
label_a5e5:
	// Read the next BASIC program byte
	lda $0200,x
	beq gotToken_a5c9
	// Does the next character match what we are searching for?
	cmp $08
	// Yes, it matches, so indicate we have the token
	beq gotToken_a5c9

foundQuotes_a5ee:
	// Not a match yet, so advance index for tokenised output
	iny
	// And write token to output
	sta $0200 - 5,y
	// Increment read index of basic program
	inx
	// Read the next BASIC byte (X should never be zero)
	bne label_a5e5

tokenDoesntMatch:
	// Restore BASIC execute pointer to start of the token we are looking at,
	// so that we can see if the next token matches
	ldx $7A
	// Increase the token ID number, since the last one didn't match
	inc $0B
	// Advance pointer in tokenlist from the end of the last token to the start
	// of the next token, ready to compare the BASIC program text with this token.
advanceToNextTokenLoop:
	jsr tokenListAdvancePointer
	jsr tokenListReadByteMinus1
	bpl advanceToNextTokenLoop
	// Check if we have reached the end of the token list
	jsr tokenListReadByte
	// If not, see if the program text matches this token
	bne compareProgramTextAndToken

	// We reached the end of the token list without a match,
	// so copy this character to the output, and
	lda $0200,x
	// Then advance to the next character of the BASIC text
	// (BPL acts as unconditional branch, because only bytes with bit 7
	// cleared can get here).
	bpl tokeniseNextProgramCharacter
tokeniseEndOfLine_a609:
	// Write end of line marker (== $00), which is conveniently in A already
	sta $0200 - 3,y
	// Decrement BASIC execute pointer high byte
	dec $7B
	// ... and set low byte to $FF
	lda #$FF
	sta $7A
	rts
}

tokenListAdvancePointer: {
	iny
	bne dontAdvanceTokenListPage
	php
	pha
	lda token_hi_page_flag
	eor #$FF
	sta token_hi_page_flag
	// XXX Why on earth do we need these three NOPs here to correctly parse the extra
	// tokens? If you remove one, then the first token no longer parses, and the later
	// ones get parsed with token number one less than it should be!
	nop
	nop
	nop
	pla
	plp
dontAdvanceTokenListPage:
	php
	pha
	txa
	pha
	tya
	tax
	bit	token_hi_page_flag
	bmi	page2
	jmp	done
page2:
done:
	pla
	tax
	pla
	plp
	rts
}

tokenListReadByte: {
	bit token_hi_page_flag
	bmi useTokenListHighPage
	lda tokenlist,y
	rts
useTokenListHighPage:
	lda tokenlist + $100,y
	rts
}

tokenListReadByteMinus1: {
	bit token_hi_page_flag
	bmi	useTokenListHighPage
	lda tokenlist - 1,y
	rts
useTokenListHighPage:
	lda tokenlist - 1 + $100,y
	rts
}

mpu_detokenize: {
	/* The C64 detokenise routine lives at $A71A-$A741.
	 * The routine is quite simple, reading through the token list,
	 * decrementing the token number each time the end of at token is
	 * found.  The only complications for us, is that we need to change
	 * the parts where the token bytes are read from the list to allow
	 * the list to be two pages long.
	 */

	// Print non-tokens directly
	bpl jump_to_a6f3
	// Print PI directly
	cmp #$ff
	beq jump_to_a6f3
	// If in quote mode, print directly
	bit $0f
	bmi jump_to_a6f3

	// At this point, we know it to be a token

	// Tokens are $80-$FE, so subtract #$7F, to renormalise them
	// to the range $01-$7F
	sec
	sbc #$7F
	// Put the normalised token number into the X register, so that
	// we can easily count down
	tax
	sty $49   // and store it somewhere necessary, apparently

	// Now get ready to find the string and output it.
	// Y is used as the offset in the token list, and gets pre-incremented
	// so we start with it equal to $00 - $01 = $FF
	ldy #$FF
	// Set token_hi_page_flag to $FF, so that when Y increments for the first
	// time, it increments token_hi_page_flag, making it $00 for the first page of
	// the token list.
	sty token_hi_page_flag


detokeniseSearchLoop:
	// Decrement token index by 1
	dex
	// If X = 0, this is the token, so read the bytes out
	beq thisIsTheToken
	// Since it is not this token, we need to skip over it
detokeniseSkipLoop:
	jsr tokenListAdvancePointer
	jsr tokenListReadByte
	bpl detokeniseSkipLoop
	// Found end of token, loop to see if the next token is it
	bmi detokeniseSearchLoop
thisIsTheToken:
	jsr tokenListAdvancePointer
	jsr tokenListReadByte
	// If it is the last byte of the token, return control to the LIST
	// command routine from the BASIC ROM
	bmi jump_list_command_finish_printing_token_a6ef
	// As it is not the end of the token, print it out
	jsr $AB47
	bne thisIsTheToken

	/* This can only be reached if the next byte in the token list is $00
	 * This could only happen in C64 BASIC if the token ID following the
	 * last is attempted to be detokenised.
	 * This is the source of the REM SHIFT+L bug, as SHIFT+L gives the
	 * character code $CC, which is exactly the token ID required, and
	 * the C64 BASIC ROM code here simply fell through the FOR routine.
	 * Actually, understanding this, makes it possible to write a program
	 * that when LISTed, actually causes code to be executed!
	 * However, this vulnerability appears not possible to be exploited,
	 * because $0201, the next byte to be read from the input buffer during
	 * the process, always has $00 in it when the FOR routine is run,
	 * causing a failure when attempting to execute the FOR command.
	 * Were this not the case, REM (SHIFT+L)I=1TO10:GOTO100, when listed
	 * would actually cause GOTO100 to be run, thus allowing LIST to
	 * actually run code. While still not a very strong form of source
	 * protection, it could have been a rather fun thing to try.

	 * Instead of having this error, we will just cause the character to
	 * be printed normally.
	 */
	ldy $49
jump_to_a6f3:
	jmp $A6F3
jump_list_command_finish_printing_token_a6ef:
	jmp $A6EF
}

mpu_execute: {
	jsr $0073
	// Is it a MEGA BASIC primary keyword?
	cmp #$CC
	bcc basic2_token
	cmp #token_first_sub_command
	bcc mpu_execute_token
	// Handle PI
	cmp #$FF
	beq basic2_token
	// not found, SYNTAX ERROR
	ldx #$0B
	jmp $A437
basic2_token:
	// $A7E7 expects Z flag set if ==$00, so update it
	cmp #$00
	jmp $A7E7
mpu_execute_token:
	// Normalise index of new token
	sec
	sbc #$CC
	asl
	// Clip it to make sure we don't have any overflow of the jump table
	and #$0E     // use correct value here
	tax
	lda newtoken_jumptable+1,x
	pha
	lda newtoken_jumptable,x
	pha
	// Get next token/character ready
	jsr $0073
	rts
}

perform_mpu: {
	cmp #tokens.get("in") // IN Keyword
	beq in
	jsr $B79E     // read byte into X
	txa
	jsr mpucmd
	jmp basic2_main_loop
in:
	jsr $0073
	jmp perform_midi_input
}

perform_midi: {
	cmp #tokens.get("voice") // VOICE Keyword
	beq voice
	cmp #tokens.get("program") // PROGRAM Keyword
	beq program
	cmp #tokens.get("ctrl") // CTRL Keyword
	beq control
	cmp #tokens.get("pitch") // PITCH Keyword
	beq pitch
	ldx #$0B
	jmp $A437
voice:
	jsr $0073
	jmp perform_note
program:
	jsr $0073
	jmp perform_program_change
control:
	jsr $0073
	jmp perform_control_change
pitch:
	jsr $0073
	jmp perform_pitch
}

perform_note: {
	cmp #$91    // ON Keyword
	beq valid_action
	cmp #tokens.get("off")
	beq valid_action
	ldx #$0B
	jmp $A437
valid_action:
	pha
	jsr $0073
	jsr $B79E   // note into X
	stx $43
	jsr $AEFD   // scan for ",", else do syntax error then warm start
	jsr $B79E   // channel into X
	stx $44
	jsr $AEFD   // scan for ",", else do syntax error then warm start
	jsr $B79E   // velocity into X
	txa
	tay
	ldx $43
	pla
	cmp #$91
	bne _noteoff
	lda $44
	jsr noteon
	jmp basic2_main_loop
_noteoff:
	lda $44
	jsr noteoff
	jmp basic2_main_loop
}

perform_program_change: {
	jsr $B79E    // new program into X
	stx $43
	jsr $AEFD    // scan for ",", else do syntax error then warm start
	jsr $B79E    // channel into X
	txa
	ldx $43
	jsr programchange
	jmp basic2_main_loop
}

perform_pitch: {
	jsr $B7EB
	txa
	ldy $14 // pitch low byte
	ldx $15 // pitch high byte
	jsr pitch
	jmp basic2_main_loop
}

perform_control_change: {
	jsr $B79E   // control ID into X
	stx $43
	jsr $AEFD   // scan for ",", else do syntax error then warm start
	jsr $B79E   // channel into X
	stx $44
	jsr $AEFD   // scan for ",", else do syntax error then warm start
	jsr $B79E   // value into X
	txa
	tay
	lda $44
	ldx $43
	jsr controlchange
	jmp basic2_main_loop
}

perform_midi_input: {
	jsr $B08B
	bit $0d
	bmi illegal_type
	sta $49
	sty $4A
	jsr bufferread
	bne read_success
	ldy #$f4      // Unused midi value, signify empty buffer
read_success:
	jsr $B3A2     // Convet Y and store in FAC
	bit $0e
	bmi convert_to_int
	jsr $BBD0     // Copy FAC to vaiable pointed to by $49-$4A
	jmp basic2_main_loop
convert_to_int:
	jsr $A9C4     // Convert FAC to int and store in variable pointed to by $49-$4A
	jmp basic2_main_loop
illegal_type:
	ldx #$16
	jmp $A437
}

mpu_basic_enable:
	ldx #(($a19c -1) - $a09e + 1)
tokencopy:
	lda $a09e,x
	sta tokenlist,x
	dex
	cpx #$ff
	bne tokencopy

	// Install new tokenise routine
	lda #<mpu_tokenize
	sta tokenise_vector
	lda #>mpu_tokenize
	sta tokenise_vector+1

	// Install new detokenise routine
	lda #<mpu_detokenize
	sta untokenise_vector
	lda #>mpu_detokenize
	sta untokenise_vector+1

	// Install new execute routine
	lda #<mpu_execute
	sta execute_vector
	lda #>mpu_execute
	sta execute_vector+1
	rts

// Tokens are $CC-$FE, so to be safe, we need to have a jump
// Addresses all are -1 to allow rts jump table
newtoken_jumptable:
	.word perform_mpu - 1
	.word perform_midi - 1

.label basic2_main_loop = $A7AE

token_hi_page_flag:
	.byte $00

