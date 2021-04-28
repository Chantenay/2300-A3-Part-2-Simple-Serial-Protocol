.syntax unified
.global main
.include "libcomp2300/macros.S"


.type main, %function
main:
  @@@ See design document for testing instructions @@@
  
  @setup
  bl init
  bl BSP_AUDIO_Buffer

  @ enable SYSCFG clock
  RCC_APB2ENR_set 0

  @ turn on the clock for GPIO ports H, B, D and E
  GPIOx_clock_enable H
  GPIOx_clock_enable B
  GPIOx_clock_enable E
  GPIOx_clock_enable D

  GPIO_configure_output_pin E, 14 @control line sender
  GPIO_configure_output_pin E, 15 @clock line sender
  GPIO_configure_output_pin E, 13 @data sender

  GPIO_configure_input_pin_it D, 0 @control line receiver
  EXTI_set_rising_edge_trigger 0
  EXTI_set_falling_edge_trigger 0
  NVIC_set ISER 6

  GPIO_configure_input_pin_it B, 3 @clock line reciever
  EXTI_set_rising_edge_trigger 3
  EXTI_set_falling_edge_trigger 3
  NVIC_set ISER 9

  GPIO_configure_input_pin_it H, 1 @data line reciever
  EXTI_set_rising_edge_trigger 1
  EXTI_set_falling_edge_trigger 1
  NVIC_set ISER 7

  @timer setup - interval of 0.25 seconds
  ldr r0, =10000
  ldr r1, =2000
  bl tim7_init 

  @set first note in sequence
  ldr r0, =data_array
  ldr r1, [r0]  
  ldr r2, =to_send
  mov r3, 24
  str r3, [r2]
  str r1, [r2, 4]

  b loop
.size main, .-main

loop:
  @@@ Sender part
  @check if the control line is on
  ldr r1, =control_line
  ldr r0, [r1]
  cmp r0, 1
  beq send @if it is, send the next note's data 

  @@@ Receiever part
  bl wave_play_next_sample @play the current note

  b loop

@sends the next note's data
send:
  ldr r4, =to_send
  ldr r5, [r4] @lenght
  ldr r6, [r4, 4] @what to send 

  cmp r5, 0 @check if there's if nothing left to send 
  ble finish_sending 

  @get digit to send
  mov r0, r5
  sub r0, 1
  lsr r1, r6, r0
  mov r7, 2
  mod r8, r1, r7

  sub r5, 1 @subtract 1 off length to send
  str r5, [r4]

  @if 0 send a 0
  cmp r8, 0
  IT EQ 
  bleq send_0

  @if 1 send a 1
  cmp r8, 1
  IT EQ 
  bleq send_1

  GPIOx_ODR_toggle E, 15 @toggle clock line

  b send 

@handles next note setup
finish_sending: 
  GPIOx_ODR_clear E, 14 @clear control line

  ldr r0, =array_counter
  ldr r1, [r0]
  add r1, 4
  str r1, [r0] @add 4 to array counter

  cmp r1, 128
  bge reset @if gone past the end of the array reset

  ldr r2, =to_send 
  ldr r3, =data_array
  ldr r4, [r3, r1] @get what to send next from array
  str r4, [r2, 4] @update what to send next in memory

  mov r5, 24
  str r5, [r2] @reset the length 

  b loop

@sents a 0 over the data line
send_0:
  push {lr}
  GPIOx_ODR_clear E, 13 @if 0 send a 0
  bl sync
  pop {lr}
  bx lr 

@sents a 1 over the data line
send_1:
  push {lr}
  GPIOx_ODR_set E, 13 @if 1 send a 1
  bl sync
  pop {lr}
  bx lr 

@resets the sequence 
reset:
  mov r0, 0
  @reset array counter
  ldr r1, =array_counter
  str r0, [r1]

  @reset to_send
  ldr r0, =data_array
  ldr r1, [r0]  
  ldr r2, =to_send
  mov r3, 24
  str r3, [r2]
  str r1, [r2, 4]

  b loop

@control line handler - PD0 - PE14
.global EXTI0_IRQHandler
.type EXTI0_IRQHandler, %function
EXTI0_IRQHandler:
  push {r4-r12, lr}

  GPIOx_IDR_read D 0 @check if falling/rising edge 

  ldr r1, =control_line @update control line status
  str r0, [r1]
  cmp r0, 0
  bne continue @check if starting to recieve / finished recieving 

  ldr r0, =read_in 
  ldr r1, [r0] @get what was read in 

  ldr r0, =freq_in @set the frequency just read in (8 last digits)
  ldr r2, =0b11111111
  and r2, r1
  str r2, [r0] @store frequency

  ldr r0, =amp_in @set the shape just read in (first digits)
  lsr r3, r1, 8
  str r3, [r0] 

  ldr r0, =read_in
  mov r1, 0
  str r1, [r0] @reset read in 

  ldr r2, =freq_in 
  ldr r0, [r2] @get the frequency just read in 
  mov r1, r3
  bl wave_change @update wave

  continue:

  EXTI_PR_clear_pending 0 @clear trigger

  pop {r4-r12, lr}
  bx lr

@clock line handler - PB3 - PE15
.global EXTI3_IRQHandler
.type EXTI3_IRQHandler, %function
EXTI3_IRQHandler:
  push {r4-r12, lr}

  EXTI_PR_clear_pending 3

  @check that control line is on
  ldr r0, =control_line
  ldr r1, [r0]
  cmp r1, 0
  beq break @if it isn't don't do anything 

  @read what's been sent 
  ldr r0, =data_line
  ldr r1, [r0] 

  @add it to end of the total thing read and store
  ldr r2, =read_in
  ldr r3, [r2] @what we're read so far

  lsl r3, 1 
  add r3, r1 @add new bit to the end 

  str r3, [r2] @store it again 

  break: 
  
  pop {r4-r12, lr}
  bx lr

@data line handler - PH1 - PE13
.global EXTI1_IRQHandler
.type EXTI1_IRQHandler, %function
EXTI1_IRQHandler:
  push {r4-r12, lr}

  @check that control line is on
  ldr r0, =control_line
  ldr r1, [r0]
  cmp r1, 0
  beq break1 @if it isn't don't do anything 

  EXTI_PR_clear_pending 1

  GPIOx_IDR_read H 1 @read incomming bit
  ldr r1, =data_line
  str r0, [r1] @store whatever was just read

  break1:

  pop {r4-r12, lr}
  bx lr

.data
.align 2 @ align memory addresses to a word boundry (leave here)
@ \/ memory entries go below \/

@data table for around the world vocal track
.global data_array
data_array:
  @first 2 digits: wave shape. 00 - sawtooth, 01 - triangle, 11 - square
  .word 0b11111111111111111000100 @196 frequency 0x7FFF amp
  .word 0b01111111111111110111001 @185 frequency 0x3FFF amp
  .word 0b00111111111111111000100 @196 frequency 0x1fff amp     
  .word 0b01111111111111111000100 @196 frequency 0x7FFF amp
  .word 0b11111111111111111011100 @220 frequency 0x3FFF amp
  .word 0b01111111111111111011100 @220 frequency 0x1fff amp  
  .word 0b00111111111111111000100 @196 frequency 0x7FFF amp
  .word 0b01111111111111111000100 @196 frequency 0x3FFF amp
  .word 0b11111111111111110111001 @185 frequency 0x1fff amp  
  .word 0b01111111111111110111001 @185 frequency 0x7FFF amp
  .word 0b00111111111111111000100 @196 frequency 0x3FFF amp
  .word 0b01111111111111111000100 @196 frequency 0x1fff amp  
  .word 0b11111111111111111110111 @247 frequency 0x7FFF amp
  .word 0b01111111111111111110111 @247 frequency 0x3FFF amp
  .word 0b00111111111111111000100 @196 frequency 0x1fff amp  
  .word 0b0 @silence 
  .word 0b01111111111111111000100 @196 frequency 0x7FFF amp
  .word 0b11111111111111110111001 @185 frequency 0x3FFF amp
  .word 0b01111111111111111000100 @196 frequency 0x1fff amp  
  .word 0b00111111111111111000100 @196 frequency 0x7FFF amp
  .word 0b01111111111111111011100 @220 frequency 0x3FFF amp
  .word 0b0 @silence 
  .word 0b11111111111111111000100 @196 frequency 0x1fff amp  
  .word 0b0 @silence 
  .word 0b01111111111111110111001 @185 frequency 0x7FFF amp
  .word 0b0 @silence 
  .word 0b00111111111111111000100 @196 frequency 0x3FFF amp
  .word 0b0 @silence 
  .word 0b01111111111111111110111 @247 frequency 0x1fff amp  
  .word 0b11111111111111111110111 @247 frequency 0x7FFF amp
  .word 0b01111111111111111000100 @196 frequency 0x3FFF amp
  .word 0b0 @silence 

@counter for array 
.global array_counter
array_counter:
  .word 0

@control line status
control_line:
  .word 0 @0 - off, 1 = on 
  
@what's currently being send over the data line
data_line: 
  .word 0

@what's been read off the data line
read_in:
  .word 0

@the frequency of the note read in 
freq_in: 
  .word 0

@the amplitude of the note read in 
amp_in: 
  .word 0

@what needs to be sent
to_send: 
  .word 0 @length of thing to send (binary length)
  .word 0 @thing to send