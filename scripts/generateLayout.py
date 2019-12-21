#!/usr/bin/env python
# By Patrik. Creates a layout for ISOCD

import sys
import os
from collections import deque

if __name__=="__main__":
    if len(sys.argv) >= 6:
        sourceDir = sys.argv[1]
        sourceDirAmigaPath = sys.argv[2]
        cdName = sys.argv[3]
        isoFileAmigaPath = sys.argv[4]
        sortByMethod = sys.argv[5].lower()
        prioritizedPaths = []
        if len(sys.argv) > 6:
        	prioritizedPaths = [sourceDir] + sys.argv[6:]

    else:
    	raise SystemExit("Usage: " + sys.argv[0].split(os.sep)[-1] + " sourceDir sourceDirAmigaPath cdName isoFileAmigaPath sortByMethod (breadth/depth) layoutFile [prioritizedPaths .. ]")

def doit(sourceDir,sourceDirAmigaPath,cdName,isoFileAmigaPath,sortByMethod,prioritizedPaths=[]):
    try:
        # set binary mode on output/error stream for Windows
        import msvcrt
        msvcrt.setmode (sys.stdout.fileno(), os.O_BINARY)
        msvcrt.setmode (sys.stderr.fileno(), os.O_BINARY)
    except ImportError:
        pass

    class PathNode:
    	def __init__(self, path, parent):
    		self.path = path
    		self.name = os.path.split(path)[1]
    		self.isDir = os.path.isdir(path)
    		self.parent = parent
    		self.children = None

    	def getName(self):
    		if self.parent == self:
    			return "<Root Dir>"
    		else:
    			return self.name

    	def getChildren(self):
    		# Cache this so we just traverse the file system the first time
    		if not self.children:
    			self.children = [PathNode(os.path.join(self.path, childPath), self) for childPath in sorted(os.listdir(self.path), key=lambda s: s.upper())]
    		return self.children

    	def getPath(self):
    		if self == self.parent:
    			return self.name
    		else:
    			return os.path.join(self.parent.getPath(), self.name)

    	def __repr__(self):
    		if self.isDir:
    			return "D{:04d}".format(self.num) + "\t" + self.getName()
    		else:
    			return "F{:04d}".format(self.parent.num) + "\t" + self.getName()

    def breadthFirstWalker(rootNode):
    	queue = deque()
    	queue.appendleft(rootNode)
    	while 0 != len(queue):
    		node = queue.pop()
    		if node.isDir:
    			queue.extendleft(node.getChildren())
    		yield node

    def depthFirstishWalker(rootNode):
    	stack = []
    	stack.append(rootNode)
    	while 0 != len(stack):
    		node = stack.pop()
    		if node.isDir:
    			stack.extend(reversed(node.getChildren()))
    		yield node

    print "0 0 3 0"
    print "2 0"
    print "8 16 40 16 32"
    print "0 1 1 0"
    print cdName
    print
    print
    print
    print
    print

    print isoFileAmigaPath
    rootNode = PathNode(sourceDir, None)
    rootNode.parent = rootNode

    dirNum = 0
    for node in breadthFirstWalker(rootNode):
    	if node.isDir:
    		dirNum += 1
    		node.num = dirNum

    print "{:04d}".format(dirNum) + "\t" + sourceDirAmigaPath
    for node in breadthFirstWalker(rootNode):
    	if node.isDir:
    		print " {:04d}".format(node.parent.num) + "\t" + node.getName()
    print

    sortByWalker = breadthFirstWalker
    if "depth" == sortByMethod:
    	sortByWalker = depthFirstishWalker

    print "H0000\t<ISO Header>"
    print "P0000\t<Path Table>"
    print "P0000\t<Path Table>"
    print "C0000\t<Trademark>"
    prioritizedNodes = {}
    for node in sortByWalker(rootNode):
    	for prioritizedPath in prioritizedPaths:
    		if not prioritizedPath in prioritizedNodes and node.path.endswith(prioritizedPath):
    			prioritizedNodes[prioritizedPath] = node

    for prioritizedPath in prioritizedPaths:
    	if prioritizedPath in prioritizedNodes:
    		print prioritizedNodes[prioritizedPath]

    for node in sortByWalker(rootNode):
    	if not node in prioritizedNodes.values():
    		print node
    print "E0000\t65536    "
