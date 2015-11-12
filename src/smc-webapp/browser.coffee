
# Calling set_window_title will set the title, but also put a notification
# count to the left of the title; if called with no arguments just updates
# the count, maintaining the previous title.
notify_count = undefined
exports.set_notify_count_function = (f) -> notify_count = f

last_title = ''
exports.set_window_title = (title) ->
    if not title?
        title = last_title
    last_title = title
    u = notify_count?()
    if u
        title = "(#{u}) #{title}"
    document.title = title