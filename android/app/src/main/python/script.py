import io, os, sys, time, threading, ctypes, inspect, traceback

def _async_raise(tid, exctype):
    tid = ctypes.c_long(tid)
    if not inspect.isclass(exctype):
        exctype = type(exctype)
    res = ctypes.pythonapi.PyThreadState_SetAsyncExc(tid, ctypes.py_object(exctype))
    if res == 0:
        raise ValueError("invalid thread id")
    elif res != 1:
        ctypes.pythonapi.PyThreadState_SetAsyncExc(tid, None)
        raise SystemError("Timeout Exception")

def stop_thread(thread):
    _async_raise(thread.ident, SystemExit)

def text_thread_run(code, result_holder):
    try:
        env = {}
        exec(code, env, env)
    except Exception as e:
        print(e)
    finally:
        result_holder['done'] = True

# This is the code to run Text functions...
def mainTextCode(code):
    result_holder = {'done': False}
    thread1 = threading.Thread(
        target=text_thread_run, args=(code, result_holder), daemon=True
    )
    thread1.start()
    # Use join() instead of a busy-wait loop — much lower CPU usage
    thread1.join(timeout=30)
    if thread1.is_alive():
        stop_thread(thread1)
        raise TimeoutError("Python execution timed out after 30s")
