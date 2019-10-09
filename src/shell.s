;;; **********************************************************************
;;;
;;;           OS extension for the HP-41 series.
;;;
;;;
;;; **********************************************************************

#include "mainframe.i"

#define IN_RATATOSK
#include "ratatosk.h"


;;; **********************************************************************
;;;
;;; A Shell is a way to provide an alternative keyboard handler and/or
;;; display routine.
;;;
;;; A Shell is defined by a structure:
;;;     ldi  .low12 myShell
;;;     gosub someRoutine
;;;
;;;          .align 4
;;; myShell: .con    kind
;;;          .con    .low12 displayRoutine
;;;          .con    .low12 standardKeys
;;;          .con    .low12 userKeys
;;;          .con    .low12 alphaKeys
;;;          .con    .low12 appendName
;;;
;;; kind
;;;   0 - system shell, means that it is a system extension. A Shell that
;;;       defines an alternative way to display numbers, like FIX-ALL would
;;;        belong to this group. Will get activated even if not at top level
;;;       of the stack if we scan down the stack as the top level Shell is
;;;       only defining some partial behavior.
;;;   1 - application shell, this means that it is only active
;;;       at top level. If found looking for a handler further down in the
;;;       stack, it is just skipped over.
;;;   2 - extension point
;;; routines - Need to be aligned 4, and 0 indicates means nothing special
;;;            is defined. An integer or complex mode would define
;;;            a standardKeys (probably set userKeys to the same), leave
;;;            alphaKeys empty.
;;;
;;;  Note: Leave other definitionBits to 0, they are for future expansion.
;;;
;;; **********************************************************************


;;; **********************************************************************
;;;
;;; activateShell - activate a given Shell
;;;
;;; In: C.X - packed pointer to shell structure
;;; Out: Returns to (P+1) if not enough free memory
;;;      Returns to (P+2) on success
;;; Uses: A, B, C, M, G, S0, S1, active PT, +2 sub levels
;;;
;;; **********************************************************************

              .section code
              .public activateShell
              .extern getbuf, insertShell, noRoom
activateShell:
              c=stk                 ; get page
              stk=c
              csr     m
              csr     m
              csr     m             ; C[3]= page address
              c=c+c   x             ; unpack pointer
              c=c+c   x
              rcr     -3            ; C[6:3]= pointer to shell
              gosub   shellHandle
              m=c                   ; M[6:0]= shell handle
              gosub   getbuf
              rtn                   ; no room

;;; Search shell stack for shell handle in M[6:0]
;;; General idea:
;;; 1. If this shell is already at the top position, we are done.
;;; 2. Scan downwards in stack looking for it.
;;; 3. If found, mark it as removed, goto 5.
;;; 4. If not in stack and there is no empty slot, push a new register
;;;    (2 empty slots) on top of stack.
;;; 5. Push the new element on top of stack letting previous elements ripple
;;;    down until we find an unused slot. We know there will be such slot as
;;;    we ensured it in the previous steps.

              s0=     0             ; empty slots not seen
              s1=     0             ; looking at first entry
              pt=     6

              b=a     x             ; B.X= buffer pointer
              c=data                ; read buffer header
              rcr     1
              c=b     x
              rcr     3
              c=0     xs
              cmex                  ; M.X= number of stack registers
                                    ; M[13:11]= buffer header address
              a=c                   ; A[6:0]= shell handle to push

10$:          c=m                   ; C.X= stack registers left
              c=c-1   x
              goc     40$           ; no more stack registers
              m=c                   ; put back updated counter
              bcex    x
              c=c+1   x
              dadd=c                ; select next stack register
              bcex    x
              c=data                ; read stack register
              ?c#0    pt            ; unused slot?
              goc     12$           ; no
              s0=     1             ; yes, remember we have seen an empty slot
12$:          ?a#c    wpt           ; is this the one we are looking for?
              goc     14$           ; no
              ?s1=1                 ; are we looking at the top entry?
              gonc    90$           ; yes, we are done
              c=0     pt            ; mark as unused
              data=c                ; write back
              goto    30$
14$:          s1=     1             ; we are now looking further down the stack
              rcr     7             ; look at second stack slot in register
              ?c#0    pt            ; unused slot?
              goc     16$           ; no
              s0=     1             ; yes, remember we have seen an empty slot
16$:          ?a#c    wpt           ; is this the one we are looking for?
              goc     10$           ; no, continue with next register
              c=0     pt            ; yes, mark as empty
              rcr     7
              data=c

              ;;  push handle on top of stack
30$:          c=m
              rcr     11            ; C.X= buffer header

32$:          c=c+1   x             ; C.X= advance to next shell stack register
              dadd=c
              bcex    x             ; B.X= shell stack pointer
              c=data
              acex    wpt           ; write pending handle to slot
              ?a#0    pt            ; unused slot?
              gonc    38$           ; yes, done
              rcr     7             ; do upper half
              acex    wpt
              rcr     7
              data=c                ; write back
              ?a#0    pt            ; unused slot?
              gonc    90$           ; yes, done
              bcex    x             ; no, go to next register
              goto    32$

38$:          data=c                ; write back
              goto    90$           ; done

40$:          ?s0=1                 ; did we encounter any empty slots?
              goc     30$           ; yes
              acex                  ; C[6:0]= shell value
              c=0     s             ; mark upper half as unused
              cmex                  ; M= shell register value to insert
              rcr     -3
              a=c     x             ; A.X= buffer header address
              gosub   insertShell   ; insert a shell register on top of stack
              rtn                   ; (P+1) no room
90$:          golong  RTNP2         ; (P+2) done


;;; **********************************************************************
;;;
;;; exitShell - dectivate a given Shell
;;; reclaimShell - reclaim a Shell at power on
;;;
;;; exitShell marks a given Shell as an unused slot, essentially removing it.
;;; We do not reclaim any memory here, it is assumed that it may be a
;;; good idea to keep one or two empty slots around. Reclaiming any
;;; buffer memory is a different mechanism.
;;;
;;; reclaimShell marks a shell to activate it.
;;;
;;; In: C.X - packed pointer to shell structure
;;; Out:
;;; Uses: A, B.X, C, M, S0, DADD, active PT, +1 sub level
;;;
;;; **********************************************************************

              .section code
              .public exitShell, reclaimShell
              .extern sysbuf

exitShell:    s0=0
              goto exitReclaim10

reclaimShell: s0=1

exitReclaim10:
              gosub   shellHandle
              m=c
              gosub   sysbuf
              rtn                   ; no shell buffer, quick exit
              data=c                ; read buffer header
              rcr     4
              c=0     xs            ; C.X= number of stack registers
              c=c-1   x             ; get 0 oriented counter
              rtnc                  ; no shell registers
              cmex                  ; M.X= number of stack registers
              pt=     5             ; we will compare lower 6 nibbles
              acex                  ; A[5:0]= shell handle to deactivate
                                    ; C.X= buffer header address

10$:          c=c+1   x             ; point to next shell register
              dadd=c
              bcex    x
              c=data
              ?a#c    wpt           ; shell in lower part?
              goc     20$           ; no
              ?s0=1                 ; reclaim?
              goc     14$           ; yes
              c=0     pt            ; no, deactivate it
12$:          data=c                ; write back
              rtn                   ; done
14$:          pt=     6
              acex    pt            ; reclaim it
              goto    12$

20$:          rcr     7             ; inspect upper part
              ?a#c    wpt           ; shell in upper part?
              goc     30$           ; no
              pt=     6
              ?s0=1                 ; yes. reclaim?
              goc     24$           ; yes
              c=0     pt            ; no, deactivate it
              goto    26$
24$:          acex    pt            ; reclaim it
26$:          rcr     7             ; realign
              goto    12$

30$:          cmex
              c=c-1   x             ; decrement register counter
              rtnc                  ; done
              cmex
              bcex    x
              goto    10$


;;; **********************************************************************
;;;
;;; releaseShells - release all Shells
;;;
;;; This is done a wake up with the idea that modules that still want their
;;; Shells should reclaim them (using reclaimShell).
;;;
;;; Out: Returns to (P+1) if no system buffer
;;;      Returns to (P+2) if there is a system buffer with
;;;          A.X= address of buffer header
;;;
;;; **********************************************************************

              .section code
              .public releaseShells
releaseShells:
              gosub   shellSetup
              rtn                   ; (P+1) no system buffer
              goto    20$           ; (P+2) system buffer, but no shells
10$:          b=a     x             ; B.X= system buffer address
              a=a+1   x             ; step to next register
              acex    x
              dadd=c
              acex    x
              c=data
              c=0     s             ; release both Shell slots
              c=0     pt
              data=c
              a=a-1   m
              gonc    10$
              abex    x             ; A.X= system buffer address
20$:          golong  RTNP2         ; return to (P+2)


;;; **********************************************************************
;;;
;;; shellHandle - look up a packed shell address and turn it into a handle
;;;
;;; In:  C[6:3] - pointer to shell descriptor
;;; Out: C[6:0] - full shell handle
;;;      C[6:3] - address of shell descriptor
;;;      C[2] - status nibble (sys/app)
;;;      C[1:0] - XROM ID of shell
;;; Uses: A, C, active PT=5
;;;
;;; **********************************************************************

              .section code
shellHandle:  cxisa                 ; read definition bits
              a=c                   ; A[6:3]= shell descriptor address
              asl     x
              asl     x             ; A[2]= status nibble (of definition bits)
              pt=     5             ; point to first address of page
              c=0     wpt
              cxisa                 ; C[1:0]= XROM ID
              acex    m             ; C[6:3]= shell descriptor address
              acex    xs            ; C[2]= status nibble (of definition bits)
              rtn


;;; **********************************************************************
;;;
;;; topAppShell - find the topmost app shell
;;; topShell - find the topmost shell
;;; nextShell - find next shell
;;;
;;; topShell can be used to locate first active shell.
;;; The following active shells can be found by successive calls to
;;; nextShell.
;;;
;;; In:  Nothing
;;; Out: Returns to (P+1) if no shells
;;;      Returns to (P+2) with
;;;          A[6:3] - pointer to shell
;;;          M - shell scan state
;;;          ST= system buffer flags, Header[1:0]
;;; Uses: A, B.X, C, DADD, S8, active PT, +2 sub levels
;;;
;;; **********************************************************************

              .section code
              .public topAppShell, topShell, nextShell
              .extern RTNP2, RTNP3
topAppShell:  s8=1
              goto    ts05
topShell:     s8=0
ts05:         gosub   shellSetup
              rtn                   ; no system buffer
              rtn                   ; no shells (though there was a buffer)
              ?st=1   Flag_NoApps   ; running without apps?
              gonc    ts08          ; no
              ?s8=1                 ; are we looking for an app?
              rtnc                  ; yes, so we cannot find anything

ts08:         a=0     s             ; first slot
ts10:         a=a+1   x
              acex    x
              dadd=c
              acex    x
              c=data
              ?c#0    pt            ; first slot in use?
              goc     ts25          ; yes
ts14:         ?c#0    s             ; second slot in use?
              goc     ts20          ; yes
ts16:         a=a-1   m
              gonc    ts10
              rtn                   ; no shell found

ts20:         rcr     7
              a=a+1   s             ; second slot
ts25:         ?s8=1                 ; looking for app shell?
              gonc    ts30          ; no, any will do, accept
              c=c-1   xs            ; is it an app shell?
              c=c-1   xs
              gonc    ts08          ; no

;;; * use this one
ts30:         acex                  ; A[6:3]= pointer to shell
              m=c                   ; M= shell scan state
              golong  RTNP2         ; found, return to (P+2)

nextShell:    s8=0                  ; looking for any shell
              c=m                   ; C= shell scan state
              pt=     6
              ?c#0    s             ; next is in upper part?
              goc     10$           ; no, need a new register
              dadd=c                ; yes, select same register
              a=c                   ; A= shell scan state
              c=data
              goto    ts14          ; go looking at second slot

10$:          a=c
              a=0     s             ; first slot
              goto    ts16          ; loop again

;;; **********************************************************************
;;;
;;; disableThisShell - end current shell
;;;
;;; Assuming that we are scanning the shell stack, disable the current
;;; shell. Intended to be used when a transient App encounters a default
;;; key that also means that it should end.
;;;
;;; In: M - shell scan state
;;; Uses: A, C, DADD, PT=6
;;;
;;; **********************************************************************

              .section code
              .public disableThisShell
disableThisShell:
              c=m
              a=c
              dadd=c
              c=data
              ?a#0    s
              goc     10$
              pt=     6
              c=0     pt
              goto    20$
10$:          c=0     s
20$:          data=c
              rtn


;;; **********************************************************************
;;;
;;; shellSetup - prepare for scanning shell stack
;;;
;;; In:  Nothing
;;; Out: Returns to (P_1) if no system buffer
;;;      Returns to (P+2) if no shells with
;;;          A.X - pointer to buffer header
;;;      Returns to (P+3) with
;;;          A.X - pointer to buffer header
;;;          A.M - number of shell registers - 1
;;;          ST= system buffer flags, Header[1:0]
;;;          PT= 6
;;;          DADD= buffer header
;;; Uses: A, B.X, C, +1 sub level
;;;
;;; **********************************************************************

              .section code
shellSetup:   gosub   sysbuf
              rtn                   ; no buffer, return to (P+1)
              c=data                ; read buffer header
              st=c
              rcr     4
              c=0     xs
              c=c-1   x
              golc    RTNP2         ; no shell registers, return to (P+2)
              c=0     m
              rcr     -3
              a=c     m
              pt=     6
              golong  RTNP3         ; there are shells, return to (P+3)


;;; **********************************************************************
;;;
;;; doDisplay - let the active display routine alter the display
;;;
;;; This entry is used by core to update the display in case it is
;;; showing normal X contents when it should be showing what the
;;; active shell wants it to.
;;;
;;; **********************************************************************

              .section code
              .public doDisplay
doDisplay:    gosub   topAppShell
              rtn
              acex    m
mayCall:      c=c+1   m             ; step to display routine
              cxisa
              ?c#0    x             ; exists?
              rtnnc                 ; no display routine

gotoPacked:   c=c+c   x
              c=c+c   x
              csr     m
              csr     m
              csr     m
              rcr     -3
              gotoc


;;; **********************************************************************
;;;
;;; keyHandler - invoke a key handler
;;;
;;; !!!! Does not return if the key is handled.
;;;
;;; In: A[6:3] - pointer to shell
;;;     S8 - set if we have already seen an application shell,
;;;          cleared otherwise. Should be cleared before making
;;;          the first of possibly successive calls to keyHandler.
;;; Out: S8 - updated to be set if we skipped an application shell
;;;
;;; **********************************************************************

              .public keyHandler
keyHandler:   acex    m
              cxisa                 ; read control word
              a=c     m             ; A[6:3]= shell pointer
              c=c-1   x
              goc     10$           ; sys shell
              c=c-1   x
              rtnnc                 ; extension point, skip this one
              ?st=1   Flag_NoApps   ; app shell, are we looking for one?
              rtnc                  ; no, skip past it
              st=1    Flag_NoApps   ; yes, do not look for any further apps
10$:          c=0     x
              dadd=c
              c=regn  14            ; get flags

              rcr     7
              cstex
              a=0     s
              ?s0=1                 ; user mode?
              goc     14$           ; yes
              a=a+1   s             ; A.S= non-zero, not user mode
              cstex
              rcr     7
              cstex
              ?s7=1                 ; alpha mode?
              gonc    16$           ; no
              a=a+1   m             ; yes
14$:          a=a+1   m             ; user mode
16$:          a=a+1   m             ; normal mode
              acex    m
              cstex
              goto    mayCall


;;; **********************************************************************
;;;
;;; shellDisplay - show active shell display and set message flag
;;;
;;; This routine is meant to be called when a shell aware module wants
;;; to show the X register before returning to mainframe. We will look
;;; at the active application shell, do its display routine if mode is
;;; appropriate and set message flag to avoid having the normal show X
;;; routine update display, only to have it overwritten soon after.
;;; After calling this routine, jump back to a suitable NFR* routine
;;; which probably is NFRC.
;;;
;;; In: Nothing, do not care about DADD or PFAD
;;; Out: Nothing
;;; Uses: Worst case everything, +3 sub levels
;;;
;;; **********************************************************************

              .public shellDisplay
shellDisplay: ?s13=1                ; running?
              rtnc                  ; yes, done
              gosub   LDSST0        ; load SS0
              ?s3=1                 ; program mode?
              rtnc                  ; yes, no display override
              ?s7=1                 ; alpha mode?
              rtnc                  ; yes, no display override
              gosub   topAppShell
              rtn                   ; (P+1) no app shell
              a=a+1   m             ; (P+2) point to display routine
              acex    m
              cxisa
              ?c#0    x             ; does it have a display routine?
              rtnnc                 ; no
              acex                  ; yes, A[6,2:0]= packed display routine
              gosub   LDSST0        ; load SS0
              s5=1                  ; set message flag
              c=st
              regn=c  14
              acex                  ; C[6,2:0]= display routine
              goto    gotoPacked    ; update display


;;; **********************************************************************
;;;
;;; extensionHandler - invoke an extension
;;;
;;; In:  C[1:0] - generic extension code
;;; Out:   Depends on extension behavior and if there is an active one.
;;;        If there are no matching generic extension, returns to the
;;;        caller.
;;;        If there is a matching generic extension, it decides on what to
;;;        do next and is extension defined.
;;;        Typical behavior include one of the following:
;;;        1. Return to extensionHandler using a normal 'rtn'. This is
;;;           typical if it is some kind of notification or broadcast.
;;;           In this case the shell stack is further searched for more
;;;           matching generic extensions that will also get the chance
;;;           to be called.
;;;        2. As a single handler that bypasses further matches by returning
;;;           to the orignal caller. This can be done using:
;;;             spopnd
;;;             rtn
;;;           Which takes us back to the original caller. It is not possible
;;;           for it to tell whether the call was handled by a generic
;;;           extension, unless some told by the return value, for example
;;;           using the N register that is not used by extensionHandler.
;;;           Another alternative is to return to (P+2) if the call was
;;;           handled (unhandled calls always return to (P+1)), this can
;;;           be done using:
;;;             golong dropRTNP2
;;;        Argument/accumulator:
;;;        You can pass information in for example N register to the
;;;        handler(s). Handler may update that information or whatever
;;;        is appropriate/useful. This is basically a protocol between
;;;        the original caller and the handlers, and is completely up to
;;;        the extension to define the protocol.
;;; Note: An extension that returns to extensionHandler must preserve
;;;       M and B.X and not leave PFAD active.
;;; Uses: A, B.X, C, M, ST, DADD, active PT, +3 sub levels
;;;
;;; **********************************************************************

              .section code
              .public extensionHandler
extensionHandler:
              st=c                  ; ST= extension code
              gosub   topShell
              rtn                   ; (P+1) no shells
              ldi     0x200         ; (P+2) go ahead and look
              c=st
              bcex    x             ; B.X= extension code to look for
10$:          acex    m             ; C[6:3]= pointer to shell descriptor
              cxisa                 ; read control word
              a=c     x
              a=a-b   x
              ?a#0    x             ; same?
              gsubnc  mayCall       ; yes, try to invoke it
              gosub   nextShell     ; not handled here, skip to next
              rtn                   ; (P+1) no more shells
              goto    10$           ; (P+2) try the next one


;;; **********************************************************************
;;;
;;; shellName - append the name of the current shell to LCD
;;;
;;; Using the shell scan state, shift in the name of the active shell
;;; from the right into the LCD.
;;; This works the same way as MESSL, but the string comes from the shell.
;;;
;;; In: C[6:3] - pointer to shell
;;; Out: LCD selected
;;; Uses: A.M, C, +1 sub level
;;;
;;; **********************************************************************

              .public shellName
              .extern unpack5
shellName:    gosub   unpack5
              nop                   ; (P+1) igonored, we assume there is a
                                    ;       defined name
              gosub   ENLCD
              golong  MESSL+1
