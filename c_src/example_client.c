#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>

#include "erl_interface.h"
#include "ei.h"

#define BUFFER_SIZE 1000

typedef struct _state_t {
  int fd;
} state_t;

void
handle_emsg(state_t* state, ErlMessage* emsg);
void
handle_send(state_t* state, ErlMessage* emsg);
ETERM*
err_term(const char* error_atom);

int main(int argc, char **argv) {
  if (argc != 5 || !strcmp(argv[1], "-h") || !strcmp(argv[1], "--help")) {
    printf("\n");
    printf("Usage: ./priv/example_client <sname> <hostname> <cookie> <tname>\n\n");
    printf("    sname      the short name you want this c-node to connect as\n");
    printf("    hostname   the hostname\n");
    printf("    cookie     the authentication cookie\n");
    printf("    tname      the target node short name to connect to\n");
    printf("\n");
    return 0;
  }

  char *sname = argv[1];
  char *hostname = argv[2];
  char *cookie = argv[3];
  char *tname = argv[4];
  const int full_name_len = strlen(sname) + 1 + strlen(hostname) + 1;
  char full_name[full_name_len];
  stpcpy(stpcpy(stpcpy(full_name, sname), "@"), hostname);
  const int target_node_len = strlen(tname) + 1 + strlen(hostname) + 1;
  char target_node[target_node_len];
  stpcpy(stpcpy(stpcpy(target_node, tname), "@"), hostname);

  struct in_addr addr;
  addr.s_addr = htonl(INADDR_ANY);

  // fd to erlang node
  state_t* state = (state_t*)malloc(sizeof(state_t));
  bool looping = true;
  int buffer_size = BUFFER_SIZE;
  unsigned char* bufferpp = (unsigned char*)malloc(BUFFER_SIZE);
  ErlMessage emsg;

  // initialize all of Erl_Interface
  erl_init(NULL, 0);

  // initialize this node
  printf("initialising %s\n", full_name); fflush(stdout);
  if (erl_connect_xinit(hostname, sname, full_name, &addr, cookie, 0) == -1)
    erl_err_quit("error erl_connect_init");

  // connect to target node
  printf("connecting to %s\n", target_node); fflush(stdout);
  if ((state->fd = erl_connect(target_node)) < 0)
    erl_err_quit("error erl_connect");

  // signal on stdout to cnode helper that we are ready
  printf("%s ready\n", full_name); fflush(stdout);

  while (looping)
  {
    // erl_xreceive_msg adapts the buffer width
    switch(erl_xreceive_msg(state->fd, &bufferpp, &buffer_size, &emsg))
    {
      case ERL_TICK:
        // ignore
        break;
      case ERL_ERROR:
        // On failure, the function returns ERL_ERROR and sets erl_errno to one of:
        //
        // EMSGSIZE
        // Buffer is too small.
        // ENOMEM
        // No more memory is available.
        // EIO
        // I/O error.
        //
        // TODO: report on erl_errno
        looping = false;
        break;
      default:
        handle_emsg(state, &emsg);
    }
  }

}

void
handle_emsg(state_t* state, ErlMessage* emsg)
{
  switch(emsg->type)
  {
    case ERL_REG_SEND:
    case ERL_SEND:
      handle_send(state, emsg);
      break;
    case ERL_LINK:
    case ERL_UNLINK:
      break;
    case ERL_EXIT:
      break;
  }

  // its our responsibility to free these pointers
  erl_free_compound(emsg->msg);
  erl_free_compound(emsg->to);
  erl_free_compound(emsg->from);
}

void
handle_send(state_t* state, ErlMessage* emsg)
{
  ETERM *msg_pattern = erl_format("{ping, Term}");
  ETERM *response;

  if (erl_match(msg_pattern, emsg->msg))
  {
    ETERM *term = erl_var_content(msg_pattern, "Term");
    response = erl_format("{pong, ~w}", term);

    // free allocated resources
    erl_free_term(term);
  }
  else
  {
    response = err_term("unknown_call");
    return;
  }

  // send response
  erl_send(state->fd, emsg->from, response);

  // free allocated resources
  erl_free_compound(response);
  erl_free_term(msg_pattern);

  // free the free-list
  erl_eterm_release();

  return;
}

ETERM*
err_term(const char* error_atom)
{
  return erl_format("{error, ~w}", erl_mk_atom(error_atom));
}

