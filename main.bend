import Base
import ./src/server.bend as Server

def main() -> IO(Unit):
  Server.run()
