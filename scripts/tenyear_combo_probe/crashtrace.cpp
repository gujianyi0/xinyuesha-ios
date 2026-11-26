// Diagnostic-only exception reporting for isolated asset probes.
#ifdef _WIN32
#include <windows.h>
#include <dbghelp.h>
#include <cstdio>

static LONG WINAPI traceCrash(EXCEPTION_POINTERS *exception) {
    auto process = GetCurrentProcess();
    SymSetOptions(SYMOPT_LOAD_LINES | SYMOPT_UNDNAME);
    SymInitialize(process, nullptr, TRUE);
    fprintf(stderr, "probe exception 0x%lx at %p\n", exception->ExceptionRecord->ExceptionCode,
            exception->ExceptionRecord->ExceptionAddress);
#ifdef _M_X64
    const auto *context=exception->ContextRecord;
    fprintf(stderr,"registers rcx=%llx rdx=%llx r8=%llx r9=%llx rax=%llx rbx=%llx rsi=%llx rdi=%llx\n",context->Rcx,context->Rdx,context->R8,context->R9,context->Rax,context->Rbx,context->Rsi,context->Rdi);
#endif
    void *frames[64];
    const auto count = CaptureStackBackTrace(0, 64, frames, nullptr);
    for (USHORT i = 0; i < count; ++i) {
        char storage[sizeof(SYMBOL_INFO) + MAX_SYM_NAME];
        auto *symbol = reinterpret_cast<SYMBOL_INFO *>(storage);
        symbol->SizeOfStruct = sizeof(SYMBOL_INFO); symbol->MaxNameLen = MAX_SYM_NAME;
        DWORD64 displacement = 0;
        IMAGEHLP_LINE64 line{}; line.SizeOfStruct = sizeof(line); DWORD lineDisplacement = 0;
        const auto address = reinterpret_cast<DWORD64>(frames[i]);
        if (SymFromAddr(process, address, &displacement, symbol))
            fprintf(stderr, "%u %s+0x%llx", i, symbol->Name, displacement);
        else fprintf(stderr, "%u %p", i, frames[i]);
        if (SymGetLineFromAddr64(process, address, &lineDisplacement, &line))
            fprintf(stderr, " %s:%lu", line.FileName, line.LineNumber);
        fprintf(stderr, "\n");
    }
    fflush(stderr);
    return EXCEPTION_EXECUTE_HANDLER;
}
void installProbeCrashTrace() { SetUnhandledExceptionFilter(traceCrash); }
#else
void installProbeCrashTrace() {}
#endif
