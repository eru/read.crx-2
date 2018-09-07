import {fix as fixUrl, parseQuery, setScheme, getScheme, tsld as getTsld, guessType} from "../core/URL.ts"
import {fadeIn, fadeOut} from "../ui/Animate.coffee"

$view = $$.C("view_write")[0]
param = parseQuery(location.search)
_args = null

export default Write =
  getArgs: ->
    return _args if _args?
    _args =
      url: fixUrl(param.get("url"))
      title: param.get("title") ? param.get("url")
      name: param.get("name") ? app.config.get("default_name")
      mail: param.get("mail") ? app.config.get("default_mail")
      message: param.get("message") ? ""
    return _args

  beforeSendFunc: ({method, requestHeaders}) ->
    origin = browser.runtime.getURL("")[...-1]
    isSameOrigin = (
      requestHeaders.some( ({name, value}) ->
        return name is "Origin" and (value is origin or value is "null")
      ) or
      !requestHeaders.includes("Origin")
    )
    return unless method is "POST" and isSameOrigin
    {url} = Write.getArgs()
    if getTsld(url) is "2ch.sc"
      url = setScheme(url, "http")
    requestHeaders.push(name: "Referer", value: url)

    # UA変更処理
    ua = app.config.get("useragent").trim()
    if ua.length > 0
      for {name}, i in requestHeaders when name is "User-Agent"
        requestHeaders[i].value = ua
        break

    return {requestHeaders}

  _insertUserCSS: ->
    style = $__("style")
    style.id = "user_css"
    style.textContent = app.config.get("user_css")
    document.head.addLast(style)
    return

  _changeTheme: (themeId) ->
    # テーマ適用
    $view.removeClass("theme_default", "theme_dark", "theme_none")
    $view.addClass("theme_#{themeId}")
    return

  setupTheme: ->
    # テーマ適用
    @_changeTheme(app.config.get("theme_id"))
    @_insertUserCSS()

    # テーマ更新反映
    app.message.on("config_updated", ({key, val}) =>
      if key is "theme_id"
        @_changeTheme(val)
      return
    )
    return

  setDOM: ->
    @setSageDOM()
    @setDefaultInput()
    @setBeforeUnload()

    $view.C("preview_button")[0].on("click", (e) ->
      e.preventDefault()

      text = $view.T("textarea")[0].value
      #行頭のスペースは削除される。複数のスペースは一つに纏められる。
      text = text.replace(/^\u0020*/g, "").replace(/\u0020+/g, " ")

      $div = $__("div").addClass("preview")
      $pre = $__("pre")
      $pre.textContent = text
      $button = $__("button").addClass("close_preview")
      $button.textContent = "戻る"
      $button.on("click", ->
        @parent().remove()
        return
      )
      $div.addLast($pre, $button)
      document.body.addLast($div)
      return
    )

    $view.C("message")[0].on("keyup", ->
      line = @value.split(/\n/).length
      $view.C("notice")[0].textContent = "#{@value.length}文字 #{line}行"
      return
    )
    return

  setSageDOM: ->
    $sage = $view.C("sage")[0]
    $mail = $view.C("mail")[0]

    if app.config.isOn("sage_flag")
      $sage.checked = true
      $mail.disabled = true
    $view.C("sage")[0].on("change", ->
      if @checked
        app.config.set("sage_flag", "on")
        $mail.disabled = true
      else
        app.config.set("sage_flag", "off")
        $mail.disabled = false
      return
    )
    return

  setDefaultInput: ->
    {name, mail, message} = Write.getArgs()
    $view.C("name")[0].value = name
    $view.C("mail")[0].value = mail
    $view.C("message")[0].value = message
    return

  setTitle: ({isThread}) ->
    {title, url} = Write.getArgs()
    title += "板" if isThread
    $h1 = $view.T("h1")[0]
    document.title = title
    $h1.textContent = title
    $h1.addClass("https") if getScheme(url) is "https"
    return

  onErrorFunc: (message) ->
    for dom from $view.$$("form input, form textarea")
      dom.disabled = false unless dom.hasClass("mail") and app.config.isOn("sage_flag")

    $notice = $view.C("notice")[0]
    if message
      $notice.textContent = "書き込み失敗 - #{message}"
    else
      $notice.textContent = ""
      fadeIn($view.C("iframe_container")[0])
    return

  setupMessage: ({timer, isThread, onSuccess, onError}) ->
    window.on("message", ({ data: {type, key, message}, source }) ->
      switch type
        when "ping"
          pong = "write_iframe_pong"
          pong += ":thread" if isThread
          source.postMessage(pong, "*")
          timer.wake()
        when "success"
          $view.C("notice")[0].textContent = "書き込み成功"
          timer.kill()
          await app.wait(message)
          onSuccess(key)
          {id} = await browser.tabs.getCurrent()
          browser.tabs.remove(id)
        when "confirm"
          fadeIn($view.C("iframe_container")[0])
          timer.kill()
        when "error"
          onError(message)
          timer.kill()
      return
    )
    return

  setupForm: (timer, isThread, getFormData) ->
    $view.C("hide_iframe")[0].on("click", ->
      timer.kill()
      $iframeContainer = $view.C("iframe_container")[0]
      do ->
        ani = await fadeOut($iframeContainer)
        ani.on("finish", ->
          $iframeContainer.T("iframe")[0].remove()
          return
        )
        return
      for dom from $view.$$("input, textarea")
        dom.disabled = false unless dom.hasClass("mail") and app.config.isOn("sage_flag")
      $view.C("notice")[0].textContent = ""
      return
    )

    $view.T("form")[0].on("submit", (e) ->
      e.preventDefault()

      for dom from $view.$$("input, textarea")
        dom.disabled = true unless dom.hasClass("mail") and app.config.isOn("sage_flag")

      {url} = Write.getArgs()
      {bbsType} = guessType(url)
      scheme = getScheme(url)

      iframeArgs =
        rcrxName: $view.C("name")[0].value
        rcrxMail: if $view.C("sage")[0].checked then "sage" else $view.C("mail")[0].value
        rcrxMessage: $view.C("message")[0].value

      if isThread
        iframeArgs.rcrxTitle = $view.C("title")[0].value

      $iframe = $__("iframe")
      $iframe.src = "/view/empty.html"
      $iframe.on("load", ->
        formData = getFormData(url.split("/"), iframeArgs, bbsType, scheme)
        #フォーム生成
        form = @contentDocument.createElement("form")
        form.setAttribute("accept-charset", formData.charset)
        form.action = formData.action
        form.method = "POST"
        for key, val of formData.input
          input = @contentDocument.createElement("input")
          input.name = key
          input.setAttribute("value", val)
          form.appendChild(input)
        for key, val of formData.textarea
          textarea = @contentDocument.createElement("textarea")
          textarea.name = key
          textarea.textContent = val
          form.appendChild(textarea)
        @contentDocument.body.appendChild(form)
        Object.getPrototypeOf(form).submit.call(form)
        return
      , once: true)
      $$.C("iframe_container")[0].addLast($iframe)

      timer.wake()
      $view.C("notice")[0].textContent = "書き込み中"
      return
    )
    return
  setBeforeUnload: ->
    window.on("beforeunload", ->
      browser.runtime.sendMessage(type: "writesize", x: screenX, y: screenY)
      return
    )
    return
  Timer: class
    _timer: null
    _TIMEOUT: 1000 * 30

    constructor: ({@onError}) ->
      return

    wake: ->
      @kill if @_timer?
      @timer = setTimeout( =>
        @onError("一定時間経過しても応答が無いため、処理を中断しました")
        return
      , @_TIMEOUT)
      return

    kill: ->
      clearTimeout(@_timer)
      @_timer = null
      return

do ->
  return if navigator.platform.includes("Win")
  font = localStorage.getItem("textar_font")
  return unless font?
  fontface = new FontFace("Textar", "url(#{font})")
  document.fonts.add(fontface)
  return
