import tweepy
import threading
import time

CONSUMER_KEY = 'U4xxxkjPvpMmZvnFPxQDzhcxU'
CONSUMER_SECRET = 'YGzZUzagjwpsZY6e2CFQPzPNEDSz4lCvq51uCFqukbxZatDVUA'
ACCESS_KEY = '1006816943704330241-NEB7VfhWYXD4AIMJFtKb36YYBxpZPI'
ACCESS_SECRET = '98yODD4qu7E97oZMvzywTmxnZLJT9fCcyEpPkYKSVx30P'


auth = tweepy.OAuthHandler(CONSUMER_KEY, CONSUMER_SECRET)
auth.set_access_token(ACCESS_KEY, ACCESS_SECRET)
api = tweepy.API(auth)

print "Getting all tweets..."

# Get all tweets for the account
# API is limited to 350 requests/hour per token
# so for testing purposes we do 10 at a time

timeline = api.user_timeline(count = 500)

print "Found: %d" % (len(timeline))
print "Removing..."

# Delete tweets one by one
def del_tweets():
    for t in timeline:
        time.sleep(1)
        api.destroy_status(t.id)

threading.Thread(target=del_tweets).start()

print "Twitter timeline removed!"
