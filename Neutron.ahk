﻿
class NeutronWindow
{
	; --- Constants ---
	
	static VERSION := 0.0
	
	; Windows Messages
	, WM_NCCALCSIZE := 0x83
	, WM_NCHITTEST := 0x84
	, WM_NCLBUTTONDOWN := 0xA1
	, WM_KEYDOWN := 0x100
	, WM_MOUSEMOVE := 0x200
	, WM_LBUTTONDOWN := 0x201
	, WM_SIZE := 0x05
	
	; Non-client hit test values (WM_NCHITTEST)
	, HT_VALUES := [[13, 12, 14], [10, 1, 11], [16, 15, 17]]
	, HT_CURSORS := [["nw", "n", "ne"], ["w", "", "e"], ["sw", "s", "se"]]
	
	; Registry keys
	, KEY_FBE := "HKEY_CURRENT_USER\Software\Microsoft\Internet Explorer\MAIN"
	. "\FeatureControl\FEATURE_BROWSER_EMULATION"
	
	; Other constants
	, EXE_NAME := A_IsCompiled ? A_ScriptName : StrSplit(A_AhkPath, "\").Pop()
	
	
	; --- Instance Variables ---
	
	; Maximum pixel inset for sizing handles to appear
	border_size := 6
	
	; The window size
	w := 800
	h := 600
	
	
	; --- Properties ---
	
	; Get the JS DOM object
	doc[]
	{
		get
		{
			return this.wb.Document
		}
	}
	
	; Get the JS Window object
	wnd[]
	{
		get
		{
			return this.wb.Document.parentWindow
		}
	}
	
	
	; --- Construction, Destruction, Meta-Functions ---
	
	__New(html)
	{
		static wb
		
		; Create necessary circular references
		this.bound := {}
		this.bound._OnMessage := this._OnMessage.Bind(this)
		
		; Bind message handlers
		for i, message in [this.WM_NCCALCSIZE, this.WM_LBUTTONDOWN, this.WM_SIZE, this.WM_KEYDOWN]
			OnMessage(message, this.bound._OnMessage)
		
		; Create and save the GUI
		; TODO: Restore previous default GUI
		Gui, New, +hWndhWnd +Resize -DPIScale
		this.hWnd := hWnd
		
		; Enable shadow
		VarSetCapacity(margins, 16, 0)
		NumPut(1337, &margins, 0, "Int")
		DllCall("Dwmapi\DwmExtendFrameIntoClientArea"
		, "UPtr", hWnd      ; HWND hWnd
		, "UPtr", &margins) ; MARGINS *pMarInset
		
		; Creating an ActiveX control with a valid URL instantiates a
		; WebBrowser, saving its object to the associated variable. The "about"
		; URL scheme allows us to start the control on either a blank page, or a
		; page with some HTML content pre-loaded by passing HTML after the
		; colon: "about:<!DOCTYPE html><body>...</body>"
		
		; Read more about the WebBrowser control here:
		; http://msdn.microsoft.com/en-us/library/aa752085
		
		; For backwards compatibility reasons, the WebBrowser control defaults
		; to IE7 emulation mode. The standard method of mitigating this is to
		; include a compatibility meta tag in the HTML, but this requires
		; tampering to the HTML and does not solve all compatibility issues.
		; By tweaking the registry before and after creation of the control we
		; can opt-out of the browser emulation feature altogether with minimal
		; impact on the rest of the system.
		
		; Read more about browser compatibility modes here:
		; https://docs.microsoft.com/en-us/archive/blogs/patricka/controlling-webbrowser-control-compatibility
		
		RegRead, fbe, % this.KEY_FBE, % this.EXE_NAME
		RegWrite, REG_DWORD, % this.KEY_FBE, % this.EXE_NAME, 0
		Gui, Add, ActiveX, vwb hWndhWB x0 y0 w800 h600, about:blank
		if (fbe = "")
			RegDelete, % this.KEY_FBE, % this.EXE_NAME
		else
			RegWrite, REG_DWORD, % this.KEY_FBE, % this.EXE_NAME, % fbe
		
		; Save the WebBrowser control to reference later
		this.wb := wb
		this.hWB := hWB
		
		; Write the given content to the page
		this.doc.write(html)
		this.doc.close()
		
		; Inject the AHK objects into the JS scope
		this.wnd.neutron := this
		this.wnd.ahk := new this.Dispatch(this)
		
		; Wait for the page to finish loading
		while wb.readyState < 4
			Sleep, 50
		
		; Show the GUI
		Gui, Show, % "w" this.w "h" this.h
		
		; Subclass the rendered Internet Explorer_Server control to intercept
		; its events, including WM_NCHITTEST and WM_NCLBUTTONDOWN.
		; Read more here: https://forum.juce.com/t/_/27937
		; And in the AutoHotkey documentation for RegisterCallback (Example 2)
		
		ControlGet, hWnd, hWnd,, Internet Explorer_Server1, % "ahk_id" this.hWnd
		this.hIES := hWnd
		
		this.pWndProc := RegisterCallback(this._WindowProc, "", 4, &this)
		this.pWndProcOld := DllCall("SetWindowLong" (A_PtrSize == 8 ? "Ptr" : "")
		, "Ptr", hWnd          ; HWND     hWnd
		, "Int", -4            ; int      nIndex (GWLP_WNDPROC)
		, "Ptr", this.pWndProc ; LONG_PTR dwNewLong
		, "Ptr") ; LONG_PTR
	}
	
	
	; --- Event Handlers ---
	
	_OnMessage(wParam, lParam, Msg, hWnd)
	{
		if (hWnd == this.hWnd)
		{
			; Handle messages for the main window
			
			if (Msg == this.WM_NCCALCSIZE)
			{
				; Size the client area to fill the entire window.
				; See this project for more information:
				; https://github.com/rossy/borderless-window
				
				; Fill client area when not maximized
				if !DllCall("IsZoomed", "UPtr", hWnd)
					return 0
				; else crop borders to prevent screen overhang
				
				; Query for the window's border size
				VarSetCapacity(windowinfo, 60, 0)
				NumPut(60, windowinfo, 0, "UInt")
				DllCall("GetWindowInfo", "UPtr", hWnd, "UPtr", &windowinfo)
				cxWindowBorders := NumGet(windowinfo, 48, "Int")
				cyWindowBorders := NumGet(windowinfo, 52, "Int")
				
				; Inset the client rect by the border size
				NumPut(NumGet(lParam+0, "Int") + cxWindowBorders, lParam+0, "Int")
				NumPut(NumGet(lParam+4, "Int") + cyWindowBorders, lParam+4, "Int")
				NumPut(NumGet(lParam+8, "Int") - cxWindowBorders, lParam+8, "Int")
				NumPut(NumGet(lParam+12, "Int") - cyWindowBorders, lParam+12, "Int")
				
				return 0
			}
			else if (Msg == this.WM_SIZE)
			{
				; Extract size from LOWORD and HIWORD (preserving sign)
				this.w := w := lParam<<48>>48
				this.h := h := lParam<<32>>48
				
				GuiControl, %hWnd%:Move, % this.hWB, w%w% h%h%
			}
		}
		else if (hWnd == this.hIES)
		{
			; Handle messages for the rendered Internet Explorer_Server
			
			if (Msg == this.WM_KEYDOWN)
			{
				; Accelerator handling code from AutoHotkey Installer
				
				if (Chr(wParam) ~= "[A-Z]" || wParam = 0x74) ; Disable Ctrl+O/L/F/N and F5.
					return
				Gui +OwnDialogs ; For threadless callbacks which interrupt this.
				pipa := ComObjQuery(this.wb, "{00000117-0000-0000-C000-000000000046}")
				VarSetCapacity(kMsg, 48), NumPut(A_GuiY, NumPut(A_GuiX
				, NumPut(A_EventInfo, NumPut(lParam, NumPut(wParam
				, NumPut(Msg, NumPut(hWnd, kMsg)))), "uint"), "int"), "int")
				Loop 2
					r := DllCall(NumGet(NumGet(1*pipa)+5*A_PtrSize), "ptr", pipa, "ptr", &kMsg)
				; Loop to work around an odd tabbing issue (it's as if there
				; is a non-existent element at the end of the tab order).
				until wParam != 9 || this.wb.document.activeElement != ""
				ObjRelease(pipa)
				if r = 0 ; S_OK: the message was translated to an accelerator.
					return 0
				return
			}
		}
	}
	
	_WindowProc(Msg, wParam, lParam)
	{
		Critical
		hWnd := this
		this := Object(A_EventInfo)
		
		if (Msg == this.WM_NCHITTEST)
		{
			; Check to see if the cursor is near the window border, which
			; should be treated as the "non-client" drag-to-resize area.
			; https://autohotkey.com/board/topic/23969-/#entry155480
			
			; Extract coordinates from LOWORD and HIWORD (preserving sign)
			x := lParam<<48>>48, y := lParam<<32>>48
			
			; Get the window position for comparison
			WinGetPos, wX, wY, wW, wH, % "ahk_id" this.hWnd
			
			; Calculate positions in the lookup tables
			row := (x < wX + this.BORDER_SIZE) ? 1 : (x >= wX + wW - this.BORDER_SIZE) ? 3 : 2
			col := (y < wY + this.BORDER_SIZE) ? 1 : (y >= wY + wH - this.BORDER_SIZE) ? 3 : 2
			
			return this.HT_VALUES[col, row]
		}
		else if (Msg == this.WM_NCLBUTTONDOWN)
		{
			; Hoist nonclient clicks to main window
			return DllCall("SendMessage", "Ptr", this.hWnd, "UInt", Msg, "UPtr", wParam, "Ptr", lParam, "Ptr")
		}
		
		; Otherwise (since above didn't return), pass all unhandled events to the original WindowProc.
		return DllCall("CallWindowProc"
		, "Ptr", this.pWndProcOld ; WNDPROC lpPrevWndFunc
		, "Ptr", hWnd             ; HWND    hWnd
		, "UInt", Msg             ; UINT    Msg
		, "UPtr", wParam          ; WPARAM  wParam
		, "Ptr", lParam           ; LPARAM  lParam
		, "Ptr") ; LRESULT
	}
	
	
	; --- Methods ---
	
	DragTitleBar()
	{
		PostMessage, this.WM_NCLBUTTONDOWN, 2, 0,, % "ahk_id" this.hWnd
	}
	
	Minimize()
	{
		Gui, % this.hWnd ":Minimize"
	}
	
	Maximize()
	{
		if DllCall("IsZoomed", "UPtr", this.hWnd)
			Gui, % this.hWnd ":Restore"
		else
			Gui, % this.hWnd ":Maximize"
	}
	
	Close()
	{
		; TODO: Function Stub
	}
	
	; --- Static Methods ---
	
	Each(htmlCollection)
	{
		return new this.Enumerable(htmlCollection)
	}
	
	; Given an HTML Form Element, construct a FormData object
	;
	; Parameters:
	;   formElement - The HTML Form Element
	;   useIdAsName - When a field's name is blank, use it's ID instead
	;
	; Returns: A FormData object
	;
	GetFormData(formElement, useIdAsName:=True)
	{
		formData := new this.FormData()
		
		for i, field in this.Each(formElement.elements)
		{
			; Discover the field's name
			name := ""
			try ; fieldset elements error when reading the name field
				name := field.name
			if (name == "" && useIdAsName)
				name := field.id
			
			; Filter against fields which should be omitted
			if (name == "" || field.disabled
				|| field.type ~= "^file|reset|submit|button$")
				continue
			
			; Handle select-multiple variants
			if (field.type == "select-multiple")
			{
				for j, option in this.Each(field.options)
					if (option.selected)
						formData.add(name, option.value)
				continue
			}
			
			; Filter against unchecked checkboxes and radios
			if (field.type ~= "^checkbox|radio$" && !field.checked)
				continue
			
			; Return the field values
			formData.add(name, field.value)
		}
		
		return formData
	}
	
	
	; --- Nested Classes ---
	
	class Dispatch
	{
		__New(parent)
		{
			this.parent := parent
		}
		
		__Call(params*)
		{
			fname := params.RemoveAt(1)
			return Func(fname).(this.parent, params*)
		}
	}
	
	class Enumerable
	{
		i := 0
		
		__New(htmlCollection)
		{
			this.collection := htmlCollection
		}
		
		_NewEnum()
		{
			return this
		}
		
		Next(ByRef i, ByRef elem)
		{
			if (this.i >= this.collection.length)
				return False
			i := this.i
			elem := this.collection.item(this.i++)
			return True
		}
	}
	
	; An OrderedDict style object designed for holding form data.
	; Allows duplicate keys.
	class FormData
	{
		names := []
		values := []
		
		; Add a field to the FormData structure
		Add(name, value)
		{
			this.names.Push(name)
			this.values.Push(value)
		}
		
		; Get an array of all values associated with a name
		All(name)
		{
			values := []
			for i, v in this.names
				if (v == name)
					values.Push(this.values[i])
			return values
		}
		
		; Allow access of a value with bracket notation
		; Retrieves the nth value with the given name
		__Get(name, n := 1)
		{
			for i, v in this.names
				if (v == name && !--n)
					return this.values[i]
		}
		
		; Allow enumeration in the order fields were added
		_NewEnum()
		{
			return {"i": 0, "base": this}
		}
		Next(ByRef name, ByRef value)
		{
			if (++this.i > this.names.length())
				return False
			name := this.names[this.i]
			value := this.values[this.i]
			return True
		}
	}
}