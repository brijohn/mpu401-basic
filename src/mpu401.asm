.disk [filename="mpu401.d64", name="MPU401", id="D0"]
{
	[name="MPU401", type="prg", segments="Default"],
}

.macro waitDDR() {
	wait:
		lda STATPORT
		and #$40
		bne wait
}

.const DATAPORT = $df00
.const STATPORT = $df01
.const CMDPORT  = $df01

.const source = $fb
.const dest   = $fd

/* bit 7 is 1 if a command recieved an ack, 0 if ack has not been recieved
 * bit 6 is set when in uart mode
 * bit 0 is set when initialized
*/
.const status = $02
.const ringBufferReadPtr = $fb
.const ringBufferWritePtr = $fc
.const irq_chain = $fd
.const ringBuffer = $cf00

*=$801 "Basic"
BasicUpstart(init)

*=$80e "Initialization"
init: {
	jsr copyram
	lda #$00
	sta status
	sta ringBufferReadPtr
	sta ringBufferWritePtr
	lda $314
	cmp #<mpuirq
	bne install_irq
	lda $315
	cmp #>mpuirq
	beq irq_installed
install_irq:
	sei
	lda $0314
	sta irq_chain
	lda $0315
	sta irq_chain+1
	lda #<mpuirq
	sta $0314
	lda #>mpuirq
	sta $0315
	cli
irq_installed:
	lda #$FF
	jsr mpucmd
	lda #$01
	ora status
	sta status
	rts
}

copyram: {
	ldx #8*2
	lda #<c000block
	sta source
	lda #>c000block
	sta source+1
	lda #00
	sta dest
	lda #$C0
	sta dest+1
ramCopy1:
	ldy #0
ramCopy2:
	lda (source),y
	sta (dest),y
	dey
	bne ramCopy2
	inc source+1
	inc dest+1
	dex
	bne ramCopy1
	rts
}

.memblock "Relocatable Code"
c000block: .segmentout[segments="HighMemory"]

.segment HighMemory [start=$c000, min=$c000, max=$cfff]
jmp mpucmd
jmp noteon
jmp noteoff
jmp programchange
jmp pitch
jmp controlchange
jmp channelpressure
jmp keypressure
jmp bufferread

mpucmd: {
	tax
	:waitDDR()
	txa
	sta CMDPORT
wait_for_ack:
	bit status       // Sets N and V status to bits 7 & 6 of status
	bvs set_flags    // bit 6 is uart mode, no ack is sent in this case
	bpl wait_for_ack
set_flags:
	cmp #$ff
	beq clear_uart
	cmp #$3f
	bne cmd_finished
	lda status
	ora #$40
	sta status
	jmp cmd_finished
clear_uart:
	lda status
	and #$bf
	sta status
cmd_finished:
	lda status
	and #$7f
	sta status
	rts
}

noteon: {
	pha
	:waitDDR()
	pla
	and #$0F
	ora #$90
	sta DATAPORT
	:waitDDR()
	txa
	and #$7f
	sta DATAPORT
	:waitDDR()
	tya
	and #$7f
	sta DATAPORT
	rts
}

noteoff: {
	pha
	:waitDDR()
	pla
	and #$0F
	ora #$80
	sta DATAPORT
	:waitDDR()
	txa
	and #$7f
	sta DATAPORT
	:waitDDR()
	tya
	and #$7f
	sta DATAPORT
	rts
}

programchange: {
	pha
	:waitDDR()
	pla
	and #$0F
	ora #$c0
	sta DATAPORT
	:waitDDR()
	txa
	and #$7f
	sta DATAPORT
	rts
}

pitch: {
	pha
	:waitDDR()
	pla
	and #$0F
	ora #$e0
	sta DATAPORT
	:waitDDR()
	tya
	and #$7f
	sta DATAPORT
	:waitDDR()
	tya
	rol
	txa
	rol
	and #$7f
	sta DATAPORT
	rts
}

controlchange: {
	pha
	:waitDDR()
	pla
	and #$0F
	ora #$b0
	sta DATAPORT
	:waitDDR()
	txa
	and #$7f
	sta DATAPORT
	:waitDDR()
	tya
	and #$7f
	sta DATAPORT
	rts
}

channelpressure: {
	pha
	:waitDDR()
	pla
	and #$0F
	ora #$d0
	sta DATAPORT
	:waitDDR()
	txa
	and #$7f
	sta DATAPORT
	rts
}

keypressure: {
	pha
	:waitDDR()
	pla
	and #$0F
	ora #$a0
	sta DATAPORT
	:waitDDR()
	txa
	and #$7f
	sta DATAPORT
	:waitDDR()
	tya
	and #$7f
	sta DATAPORT
	rts
}

bufferread: {
	ldx ringBufferReadPtr
	cpx ringBufferWritePtr
	beq buffer_empty
	lda ringBuffer,x
	tay
	inx
	txa
	and #$FF
	sta ringBufferReadPtr
	lda #1                  // clear zero flag, return value in y
buffer_empty:
	rts
}

mpuirq: {
	lda STATPORT
	bmi irq_next
	lda DATAPORT
	jsr mpurx
irq_next:
	jmp (irq_chain)
}

mpurx: {
	cmp #$FE
	bne store_midi_byte
	lda status
	ora #$80
	sta status
	rts
store_midi_byte:
	ldx ringBufferWritePtr
	sta ringBuffer,x
	inx
	txa
	and #$FF
	sta ringBufferWritePtr
	rts
}
