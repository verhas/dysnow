class Segment:
    def __init__(self, name, filename):
        self.name = name
        self.filename = filename
        self.text = []
        self.next = None
        self.previous = None
        self.modified = False
        self.parameters = {}

    def __str__(self):
        return "[Segment %s/%s %s]" % (self.filename, self.name, "(m)" if self.modified else "")

    def add(self, line):
        self.text.append(line)

    def parameter(self, key):
        return key in self.parameters and self.parameters[key]

class File:
    def __init__(self, filename, segments):
        self.name = filename
        self.segments = segments

    def modified(self):
        return any([segment.modified for segment in self.segments])
