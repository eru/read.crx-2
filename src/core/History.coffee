###*
@class app.History
@static
###
class app.History
  @_openDB: ->
    unless @_openDBPromise?
      @_openDBPromise = $.Deferred((d) ->
        db = openDatabase("History", "", "History", 0)
        db.transaction(
          (transaction) ->
            transaction.executeSql """
              CREATE TABLE IF NOT EXISTS History(
                url TEXT NOT NULL,
                title TEXT NOT NULL,
                date INTEGER NOT NULL
              )
            """
            return
          -> d.reject(); return
          -> d.resolve(db); return
        )
      ).promise()
    @_openDBPromise

  ###*
  @method add
  @param {String} url
  @param {String} title
  @param {Number} date
  @return {Promise}
  ###
  @add: (url, title, date) ->
    if app.assert_arg("History.add", ["string", "string", "number"], arguments)
      return $.Deferred().reject().promise()

    @_openDB().then((db) -> $.Deferred (d) ->
      db.transaction(
        (transaction) ->
          transaction.executeSql(
            "INSERT INTO History values(?, ?, ?)"
            [url, title, date]
          )
          return
        ->
          app.log("error", "History.add: データの格納に失敗しました")
          d.reject()
          return
        -> d.resolve(); return
      )
      return
    )
    .promise()

  ###*
  @method remove
  @param {String} url
  @param {Number} date
  @return {Promise}
  ###
  @remove: (url, date) ->
    if (
      (date? and app.assert_arg("History.remove", ["string", "number"], arguments)) or
      app.assert_arg("History.remove", ["string"], arguments)
    )
      return $.Deferred().reject().promise()

    @_openDB().then((db) -> $.Deferred (d) ->
      db.transaction(
        (transaction) ->
          if date?
            transaction.executeSql("DELETE FROM History WHERE (url = ? AND (date BETWEEN ? AND ?+60000-1))", [url, date, date])
          else
            transaction.executeSql("DELETE FROM History WHERE url = ?", [url])
          return
        ->
          app.log("error", "History.remove: トランザクション中断")
          d.reject()
          return
        ->
          d.resolve()
          return
      )
      return
    )
    .promise()

  ###*
  @method get
  @param {Number} offset
  @param {Number} limit
  @return {Promise}
  ###
  @get: (offset = -1, limit = -1) ->
    if app.assert_arg("History.get", ["number", "number"], [offset, limit])
      return $.Deferred().reject().promise()

    @_openDB().then((db) -> $.Deferred (d) ->
      db.readTransaction(
        (transaction) ->
          transaction.executeSql(
            "SELECT * FROM History ORDER BY date DESC LIMIT ? OFFSET ?"
            [limit, offset]
            (transaction, result) ->
              data = []
              key = 0
              length = result.rows.length
              while key < length
                item = result.rows.item(key)
                item.is_https = (app.url.getScheme(item.url) is "https")
                data.push(item)
                key++
              d.resolve(data)
              return
          )
          return
        ->
          app.log("error", "History.get: トランザクション中断")
          d.reject()
          return
      )
    )
    .promise()

  ###*
  @method get_all
  @return {Promise}
  ###
  @get_all: () ->
    @_openDB().then((db) -> $.Deferred (d) ->
      db.readTransaction(
        (transaction) ->
          transaction.executeSql(
            "SELECT * FROM History"
            []
            (transaction, result) ->
              d.resolve(result.rows)
              return
          )
          return
        ->
          app.log("error", "History.get_all: トランザクション中断")
          d.reject()
          return
      )
    )
    .promise()

  ###*
  @method count
  @return {Promise}
  ###
  @count: ->
    @_openDB().then((db) -> $.Deferred (d) ->
      db.readTransaction(
        (transaction) ->
          transaction.executeSql(
            "SELECT count() FROM History"
            []
            (transaction, result) ->
              d.resolve(result.rows.item(0)["count()"])
              return
          )
          return
        ->
          app.log("error", "History.count: トランザクション中断")
          d.reject()
          return
      )
    )
    .promise()

  ###*
  @method clear
  @param {Number} offset
  @return {Promise}
  ###
  @clear = (offset) ->
    if offset? and app.assert_arg("History.clear", ["number"], arguments)
      return $.Deferred().reject().promise()

    @_openDB().then((db) -> $.Deferred (d) ->
      db.transaction(
        (transaction) ->
          if typeof offset is "number"
            transaction.executeSql("DELETE FROM History WHERE rowid < (SELECT rowid FROM History ORDER BY date DESC LIMIT 1 OFFSET ?)", [offset - 1])
          else
            transaction.executeSql("DELETE FROM History")
          return
        ->
          app.log("error", "History.clear: トランザクション中断")
          d.reject()
          return
        ->
          d.resolve()
          return
      )
      return
    )
    .promise()

  ###*
  @method clearRange
  @param {Number} day
  @return {Promise}
  ###
  @clearRange = (day) ->
    if app.assert_arg("History.clearRange", ["number"], arguments)
      return $.Deferred().reject().promise()

    @_openDB().then((db) -> $.Deferred (d) ->
      db.transaction(
        (transaction) ->
          dayUnix = Date.now()-86400000*day
          transaction.executeSql("DELETE FROM History WHERE date < ?", [dayUnix])
          return
        ->
          app.log("error", "History.clearRange: トランザクション中断")
          d.reject()
          return
        ->
          d.resolve()
          return
      )
      return
    )
    .promise()
