#include <iostream>
#include <signal.h>
#include <unistd.h>

using namespace std;

static bool running = true;

void signal_handler(int) { running = false; }

int main() {
  signal(SIGTERM, signal_handler);
  signal(SIGINT, signal_handler);

  cout << "Hello World from Yocto! PID: " << getpid() << endl;

  while (running) {
    sleep(5);
  }

  cout << "Service exiting cleanly" << endl;
  return 0;
}
