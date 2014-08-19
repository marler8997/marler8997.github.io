import std.stdio;
import std.string;

int main(string[] args)
{
  enum State {initial, insideDefs}
  State state = State.initial;

  foreach(line; stdin.byLine(KeepTerminator.no)) {

    final switch(state) {
    case State.initial:
      int indexOfDefs = line.indexOf("<defs>");
      if(indexOfDefs >= 0) {
	state = State.insideDefs;
	write(line[0..indexOfDefs]);
	writeln(line[indexOfDefs + 6..$]);
      } else {
	writeln(line);
      }
      break;
    case State.insideDefs:
      int indexOfDefs = line.indexOf("</defs>");
      if(indexOfDefs >= 0) {
	line = line[indexOfDefs + 7..$];
	state = State.initial;
	writeln(line);
      }
      break;
    }
  }

  return 0;
}