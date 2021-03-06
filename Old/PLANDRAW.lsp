;;;;;;;[  Plan Drawing  ];;;;;;;;;;;;;;;;;;;;;;;;;
;;                                              ;;
;;  Draws centerline and top rail, places       ;;
;;  intermediate posts, and dimensions all.     ;;
;;                                              ;;
;;::::::::::::::::::::::::::::::::::::::::::::::;;
;;                                              ;;
;;  Author: J.D. Sandifer  (Copyright 2015)     ;;
;;  Written: 10/28/2015                         ;;
;;                                              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                              ;;
;;  11/08/2015                                  ;;
;;  - Added infill counting aspect to           ;;
;;    function.                                 ;;
;;                                              ;;
;;  11/09/2015                                  ;;
;;  - Began work on adding dimensions.          ;;
;;  - Changed RoundUpInt to use RoundUpTo       ;;
;;    (legacy support).                         ;;
;;                                              ;;
;;  11/10/2015                                  ;;
;;  - Added error handling function.            ;;
;;  - Added dimensioning feature.               ;;
;;  - Added infill stock list counting          ;;
;;    feature. This is starting to be awesome!  ;;
;;  - Added feature that changes dimension      ;;
;;    text into "EQ" and "(dim)" over "(#X)".   ;;
;;  - Added mline drawing & inserting end       ;;
;;    plates!!! (Requires TOP_RAIL mlstyle.)    ;;
;;                                              ;;
;;  11/16/2015                                  ;;
;;  - Added user input back.                    ;;
;;                                              ;;
;;  12/02/2015 - JD                             ;;
;;  - Added rubber band feature to point        ;;
;;    picking.                                  ;;
;;  - Changed endplate insertion to railLayer.  ;;
;;                                              ;;
;;  01/19/2016                                  ;;
;;  - Dimension label is now at second-to-last  ;;
;;    dim (just distance on a single dim).      ;;
;;  - Moved helper functions to separate file.  ;;
;;                                              ;;
;;  03/31/2016                                  ;;
;;  - Added post call-out placement.            ;;
;;                                              ;;
;;  04/04/2016                                  ;;
;;  - Made post tag placement conditional.      ;;
;;    (Only does it if it's a cable railing.)   ;;
;;                                              ;;
;;  Todo:                                       ;;
;;  - Combine with PlanDrawGoal & Comm w/       ;;
;;    appropriate options.                      ;;
;;  - Add top rail counting?                    ;;
;;  - Add choice of post spacing with default.  ;;
;;    Ditto on rail width.                      ;;
;;  - Revise copy on prompts.                   ;;
;;  - Check for endplate block, top_rail        ;;
;;    mline, and current layers and blocks.     ;;
;;                                              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun C:plandraw (/ intPostBlock ctrLineLayer postLayer dimLayer dimOffset
						   snapMode infillStockLength postSpacing railWidth
							isCableRailing isPicketRailing cableOffsetDistance
							tagOffsetDistance tagLayer tagBlock cableLayer)
	
   (command "._UNDO" "_Begin")		; Start UNDO group
	
   ; Save system variables and change to needed values
   (JD:ClearVars 'systemVariables)
   (JD:Save&ChangeVar "cmdEcho" 'systemVariables 0)
   (JD:Save&ChangeVar "attreq" 'systemVariables 0)
   (JD:Save&ChangeVar "blipmode" 'systemVariables 0)
   (JD:SaveVar "osmode" 'systemVariables)
   (JD:SaveVar "clayer" 'systemVariables)
   
   ; Set block names
   (setq intPostBlock "P-TRIM")
   (setq endPlateBlock "end_plate")
	(setq tagBlock "POST-DRILLED CALL-OUT")
	; layer names
   (setq ctrLineLayer "Center")
   (setq postLayer "Detail")
   (setq dimLayer "Dims")
   (setq railLayer "1")
	(setq tagLayer "POST-TAG")
	(setq cableLayer "Cable")
	; and other options
   (setq dimOffset "24")			; String means easy concatenation later
	(setq tagOffsetDistance 9)
	(setq cableOffsetDistance 12)
	(setq snapMode 64)
	(setq infillStockLength 180)
	
	; Get user input?
   ;(setq postSpacing (getreal "\nMax post spacing in inches:"))
	(setq postSpacing 48)
   ;(setq railWidth (getreal "\nRail width in inches:"))
	(setq railWidth "2-11/16")		; String or integer works here
	(setq isCableRailing T)
	(setq isPicketRailing nil)
	
   ;(ResetInfillCutList)
   
   (PlanDrawTool)			; Actual work done in this function

   (JD:ResetAllVars 'systemVariables)
   (command "._UNDO" "_End")		; End UNDO group
   
   (princ))			; Hide last return value (clean exit)



;;; Error handling function - prints error message nicely and resets system variables

(defun *error* (msg)
   (princ "\n")
   (princ msg)

   (JD:ResetAllVars 'systemVariables)
   
   (princ))			; Hide last return value (clean exit)



;;; Actual plan drawing tool

(defun PlanDrawTool ( /  Pt1 Pt2 centerLine
		       spaces lineLength infillLength
		       lineAngle isFirstTime pointList)

   (setvar "osmode" snapMode)
   (setq Pt1 (getpoint "\nChoose first point:"))
   (setq pointList (list Pt1))
   (setq isFirstTime "True")
	
   ; (Start loop for drawing each run)
   (while (/= (setq Pt2 (getpoint Pt1 "\nChoose next point:")) nil)
      ;; Keep a list of the selected points for later use
		(setq pointList (append pointList (list Pt2)))
      
		;; Change snap mode so it doesn't interfere with auto-drawing
		(setvar "osmode" 0)

		;; Main calculations
      (setq lineAngle (angle Pt1 Pt2))
      (setq lineLength (distance Pt1 Pt2))
      (setq spaces (RoundUpInt (/ lineLength postSpacing)))
		(setq spaceLength (/ lineLength spaces))
		
		;; Insert the starting endplate if this is the first post
		(if isFirstTime
         (progn
            (setvar "clayer" railLayer)
            (command "insert" endPlateBlock "y" railWidth "r" 
					(angtos (- lineAngle PI) 0 9) Pt1)
            (setq isFirstTime nil)))
      
		;; Place mid posts if needed
      (if (>= spaces 2)
			(progn
				(setvar "clayer" postLayer)
				(command "line" Pt1 Pt2 "")
				(setq centerLine (entlast))
				(command "divide" centerLine "B" intPostBlock "Y" spaces)
				(entdel centerLine)))

      ;; This section sets up points for dimensions and draws them
		;; using a loop to go through segment by segment
      (setq currentPt Pt1)
		(setq currentPtList (list Pt1))
      (setq dimIndex spaces)	; spaces should always be at least 1
      (while (> dimIndex 0)
         ;; Calculate next point and add it to the list for this section
			(setq nextPt (polar currentPt lineAngle spaceLength))
			(setq currentPtList (append currentPtList (list nextPt)))
			
			;; Draw the centerline (pline)
			(setvar "clayer" ctrLineLayer)
			(command "._pline" currentPt nextPt "")
			
         (setq offsetString (strcat "@" dimOffset "<" 
												(angtos (- lineAngle (/ PI 2)) 0 9)))
         (setvar "clayer" dimLayer)
			(command "._dimaligned" currentPt nextPt offsetString)
			; Get last dimension.
			(setq lastDim (entget (entlast)))
			;; Is this the second-to-last one? If so use the full label.
			;; Otherwise, just label it "EQ". (Unless there's only one.)
			(cond
				((and (= dimIndex 1) (= spaces 1)))
				((= dimIndex 2)
					(setq label (strcat "<>\\X(" (itoa spaces) "X)"))
					(entmod (subst (cons 1 label) (assoc 1 lastDim) lastDim)))
				(T
					(entmod (subst (cons 1 "EQ") (assoc 1 lastDim) lastDim))))
			
			;; add post call out for each intermediate post
			(if (and (> dimIndex 1)	isCableRailing)
				(progn
					(setq postTagPt (polar nextPt (+ (/ PI 2) lineAngle) 		
												  tagOffsetDistance))
					(setvar "clayer" tagLayer)
					(command "._insert" tagBlock "s" 1 "r" 0 postTagPt)))
								
			; prep for next loop (dimensioning & call-outs on current segment)
			(setq currentPt nextPt)
			(setq dimIndex (1- dimIndex)))
			
		;; Draw centerline (pline) - when I figure out how to feed in the pts
		;(setvar "clayer" ctrLineLayer)
		;(command "._pline" currentPtList "")
      
      ;; Prep for next loop (next railing segment)
		(setq Pt1 Pt2)
      (setvar "osmode" snapMode))      

   (setvar "osmode" 0)
   
	;(if endPlateBlock
		(setq insertAngle (angtos lineAngle 0 9))
		(setvar "clayer" railLayer)
		(command "insert" endPlateBlock "y" railWidth "r" insertAngle Pt1)

   (setvar "clayer" railLayer)
   (setq settingsList (list "_.mline" "justification" "zero" "scale" railWidth "style" "TOP_RAIL"))
   (setq settingsList (append settingsList pointList (list "")))
   (apply 'command settingsList) 
	
	(cond (isCableRailing
		(setvar "clayer" cableLayer)
		(DrawCableLine pointList cableOffsetDistance)))
   
   (setvar "dimzin" 8)
		
   (princ))
	
	
	
;|========={ Draw cable lines }=============|;
;| Draw polyline for cable run base on      |;
;| a provided point list and distance.      |;
;|------------------------------------------|;
;| Author: J.D. Sandifer    Rev: 03/31/2016 |;
;|==========================================|;

(defun DrawCableLine (pointList cableOffsetDistance / 
										  Pt1 Pt2 Pt3 lineAngle offsetAngle
										  Pt1offset Pt2offset lastPt1offset
										  lastLineAngle)

	(JD:ChangeVar "osmode" 0)
	
	(setq Pt1 (car pointList))
	(setq pointList (cdr pointList))
	
	(setq Pt2 (car pointList))
	(setq pointList (cdr pointList))
	
	(setq lineAngle (angle Pt1 Pt2))
	(setq offsetAngle (- lineAngle (/ PI 2)))
		
	(setq Pt1offset (polar Pt1 offsetAngle cableOffsetDistance))	
	(setq Pt2offset (polar Pt2 offsetAngle cableOffsetDistance))
	
	(command "._line" Pt1offset Pt2offset "")
	
	(setq lastPt1offset Pt2offset)
	(setq lastLineAngle lineAngle)
	(setq Pt1 Pt2)
	
	(foreach Pt2 pointList
		
		(setq lineAngle (angle Pt1 Pt2))
		(setq offsetAngle (- lineAngle (/ PI 2)))
		(setq oldOffsetAngle (- lastLineAngle (/ PI 2)))
		
		(setq Pt1offset (polar Pt1 offsetAngle cableOffsetDistance))
		(setq Pt2offset (polar Pt2 offsetAngle cableOffsetDistance))
		
		(command "._arc" "c" Pt1 lastPt1offset Pt1offset)
		(command "._line" Pt1offset Pt2offset "")
		
		; Prep for next round
		(setq lastPt1offset Pt2offset)
		(setq lastLineAngle lineAngle)
		(setq Pt1 Pt2))
		
	(princ))

	
;|=========={ Get point list }==============|;
;| Get a series of points from the user     |;
;| and return a list of the points.         |;
;|------------------------------------------|;
;| Author: J.D. Sandifer    Rev: 03/22/2016 |;
;|==========================================|;


(defun GetPointList ( / selectedPoint lastPoint pointList)

	(setq selectedPoint (getpoint "\nChoose first point:"))
	(setq pointList (append pointlist (list selectedPoint)))
	(setq lastPoint selectedPoint)

	(while (/= 
		(setq selectedPoint (getpoint lastPoint "\nChoose next point:"))
		nil)
		(setq pointList (append pointlist (list selectedPoint)))
		(setq lastPoint selectedPoint))
      
	pointList)

 

(princ)		; Clean load 