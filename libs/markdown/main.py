import threading
from processLine import processLine
import sys

for line in sys.stdin:
	thread = threading.Thread(target=processLine, args=(line,))
	thread.start()
