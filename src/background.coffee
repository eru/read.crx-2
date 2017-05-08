chrome.browserAction.onClicked.addListener( ->
  chrome.tabs.create({url: "/view/index.html"})
)
