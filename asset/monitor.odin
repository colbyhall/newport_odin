package asset

import "core:sys/win32"
import "core:c"
import "core:fmt"
import "core:sys/windows"
import "core:strings"
import "core:os"
import "core:mem"
import "core:log"

import "../core"

File_Event :: struct {
    using base : core.Event,

    path : string,
}

File_Created_Event  :: distinct File_Event;
File_Deleted_Event  :: distinct File_Event;
File_Modified_Event :: distinct File_Event;

Directory_Monitor :: struct {
    handle     : windows.HANDLE,
    dispatcher : core.Event_Dispatcher,
}

monitor_directory :: proc(path: string, recursive := false) -> (Directory_Monitor, bool) {
    _error :: proc(args: ..any) -> (Directory_Monitor, bool) {
        fmt.eprintln("[Monitor]", args);
        return {}, false;
    }

    if !os.exists(path) do return _error("Directory does not exist:", path);
    path := strings.clone_to_cstring(path, context.temp_allocator);

    filter : u32 = win32.FILE_NOTIFY_CHANGE_LAST_WRITE | win32.FILE_NOTIFY_CHANGE_FILE_NAME | win32.FILE_NOTIFY_CHANGE_CREATION;

    handle := win32.find_first_change_notification_a(path, win32.Bool(recursive), filter);
    if handle == nil do return _error("Failed to create win32 change notifier:", win32.get_last_error());

    return Directory_Monitor{ handle = auto_cast handle }, true;
}

stop_monitoring :: proc(dirmon : ^Directory_Monitor) {
    // if dirmon.file != nil do windows.CancelIo(dirmon.file);
    // if dirmon.file != nil do windows.CloseHandle(dirmon.file);
    // if dirmon.io   != nil do windows.CloseHandle(dirmon.io);
    // dirmon^ = {};
}

poll_monitor :: proc(using dir_monitor : ^Directory_Monitor) -> bool {
    if handle == nil do return false;

    wait_status := win32.wait_for_single_object(auto_cast handle, 0);
    if wait_status == win32.WAIT_TIMEOUT do return false;

    return true;

    // BUFFER_SIZE :: 2048;
    // buffer := [BUFFER_SIZE]u8;

    // if !win32.read_directory_changes_w(win32.Handle(dirmon.file), &buffer[0], BUFFER_SIZE, dirmon.recursive, notify_filter, nil, &dirmon.overlapped, nil) {
    //     stop_monitoring(dirmon);
    //     return false;
    // }

    // // if bytes_read == 0 do return key != nil;

    // // Process the changes and dispatch those events
    // base    := uintptr(&buffer[0]);
    // current := 0;
    // for {
    //     it := cast(^win32.File_Notify_Information)rawptr(base + uintptr(current));

    //     path := win32.wstring_to_utf8(cast(win32.Wstring)&it.file_name[0], int(it.file_name_length));

    //     switch it.action {
    //     case win32.FILE_ACTION_ADDED, win32.FILE_ACTION_RENAMED_NEW_NAME:
    //         e : File_Created_Event;

    //         e.path = path;

    //         core.dispatch_event(&dirmon.dispatcher, &e);
    //     case win32.FILE_ACTION_REMOVED, win32.FILE_ACTION_RENAMED_OLD_NAME:
    //         e : File_Deleted_Event;

    //         e.path = path;

    //         core.dispatch_event(&dirmon.dispatcher, &e);
    //     case win32.FILE_ACTION_MODIFIED:
    //         e : File_Modified_Event;

    //         e.path = path;

    //         core.dispatch_event(&dirmon.dispatcher, &e);
    //     case: unimplemented();
    //     }

    //     if it.next_entry_offset == 0 do break;
    //     current += int(it.next_entry_offset);
    // }

    // return key != nil;
}

foreign import "system:kernel32.lib"

FILE_LIST_DIRECTORY :: 0x1;

@(default_calling_convention = "std")
foreign kernel32 {
    @(link_name="CreateIoCompletionPort") CreateIoCompletionPort :: proc(file_handle                  : windows.HANDLE, 
                                                                         existing_completion_port     : windows.HANDLE,
                                                                         completion_key               : ^c.ulong,
                                                                         number_of_concurrent_threads : u32) -> windows.HANDLE ---;

    @(link_name="GetQueuedCompletionStatus") GetQueuedCompletionStatus :: proc(completion_port: windows.HANDLE,
                                                                               number_of_bytes_transferred : ^u32,
                                                                               completion_key              : ^^c.ulong,
                                                                               overlapped                  : ^^win32.Overlapped,
                                                                               milliseconds                : u32) -> bool ---;

    @(link_name="SetLastError") SetLastError :: proc(error_code : u32) ---;
}

// package asset

// import "core:sys/win32"
// import "core:c"
// import "core:fmt"
// import "core:sys/windows"
// import "core:strings"
// import "core:os"
// import "core:mem"
// import "core:log"

// import "../core"

// exists :: os.exists;

// // @NOTE(colby): This was created by JHarler. Original can be found here https://gist.github.com/jharler/a191a41ce3846d0b3c9918d15e9608b5

// File_Event :: struct {
//     using base : core.Event,

//     path : string,
// }

// File_Created_Event  :: distinct File_Event;
// File_Deleted_Event  :: distinct File_Event;
// File_Modified_Event :: distinct File_Event;

// Directory_Monitor :: struct {
//     io               : windows.HANDLE,
//     file             : windows.HANDLE,
//     file_notify_info : win32.File_Notify_Information,
//     overlapped       : win32.Overlapped,
//     recursive        : win32.Bool,

//     dispatcher : core.Event_Dispatcher,
// }

// monitor_directory :: proc(directory: string, recursive := false) -> (Directory_Monitor, bool) {
//     if !exists(directory) {
//         return _error("directory does not exist:", directory);
//     }

//     dirmon : Directory_Monitor = { recursive = win32.Bool(recursive), };

//     failed := true;
//     defer {
//         if failed do stop_monitoring(&dirmon); // do cleanup on anything that did succeed
//     }

//     dirmon.io = CreateIoCompletionPort(windows.INVALID_HANDLE, nil, nil, 1);
//     if dirmon.io == nil {
//         return _error("unable to monitor directory: {0} (completion port) [error: {1}]\n", directory, win32.get_last_error());
//     }

//     directory := strings.clone_to_cstring(directory, context.temp_allocator);

//     dirmon.file = windows.HANDLE(win32.create_file_a(directory,
//                                 FILE_LIST_DIRECTORY,
//                                 win32.FILE_SHARE_READ | win32.FILE_SHARE_DELETE |win32.FILE_SHARE_WRITE, nil,
//                                 win32.OPEN_EXISTING,
//                                 win32.FILE_FLAG_BACKUP_SEMANTICS | win32.FILE_FLAG_OVERLAPPED, nil));

//     if dirmon.file == nil {
//         return _error("unable to monitor directory: {0} (open directory) [error: {1}]\n", directory, win32.get_last_error());
//     }

//     if CreateIoCompletionPort(dirmon.file, dirmon.io, (^c.ulong)(dirmon.file), 0) == nil {
//         return _error("unable to monitor directory: {0} (associate port) [error: {1}]\n", directory, win32.get_last_error());
//     }

//     notify_filter : u32 = win32.FILE_NOTIFY_CHANGE_CREATION | win32.FILE_NOTIFY_CHANGE_FILE_NAME | win32.FILE_NOTIFY_CHANGE_DIR_NAME |
//                           win32.FILE_NOTIFY_CHANGE_ATTRIBUTES | win32.FILE_NOTIFY_CHANGE_SIZE | win32.FILE_NOTIFY_CHANGE_LAST_WRITE | win32.FILE_NOTIFY_CHANGE_SECURITY;

//     if !win32.read_directory_changes_w(win32.Handle(dirmon.file), rawptr(&dirmon.file_notify_info), size_of(dirmon.file_notify_info), dirmon.recursive, notify_filter,
//                                        nil, &dirmon.overlapped, nil) {
//         return _error("unable to monitor directory: {0} (read directory) [error: {1}]\n", directory, win32.get_last_error());
//     }

//     failed = false;

//     return dirmon, true;

//     _error :: proc(args: ..any) -> (Directory_Monitor, bool) {
//         fmt.eprintln(args);
//         return {}, false;
//     }
// }

// stop_monitoring :: proc(dirmon : ^Directory_Monitor) {
//     if dirmon.file != nil do windows.CancelIo(dirmon.file);
//     if dirmon.file != nil do windows.CloseHandle(dirmon.file);
//     if dirmon.io   != nil do windows.CloseHandle(dirmon.io);
//     dirmon^ = {};
// }

// poll_monitor :: proc(dirmon : ^Directory_Monitor) -> bool {
//     if dirmon == nil || dirmon.file == nil do return false;

//     bytes_read : u32;
//     key : ^c.ulong;
//     overlapped : ^win32.Overlapped;

//     if !GetQueuedCompletionStatus(dirmon.io, &bytes_read, &key, &overlapped, 0) {
//         return false;
//     }


//     fmt.println(bytes_read, key, overlapped);

//     notify_filter : u32 = win32.FILE_NOTIFY_CHANGE_CREATION | win32.FILE_NOTIFY_CHANGE_FILE_NAME | win32.FILE_NOTIFY_CHANGE_DIR_NAME | 
//         win32.FILE_NOTIFY_CHANGE_ATTRIBUTES | win32.FILE_NOTIFY_CHANGE_SIZE | win32.FILE_NOTIFY_CHANGE_LAST_WRITE | win32.FILE_NOTIFY_CHANGE_SECURITY;


//     buffer := make([]u8, int(bytes_read + 1), context.temp_allocator);

//     if !win32.read_directory_changes_w(win32.Handle(dirmon.file), &buffer[0], auto_cast len(buffer), dirmon.recursive, notify_filter, nil, &dirmon.overlapped, nil) {
//         stop_monitoring(dirmon);
//         return false;
//     }

//     // if bytes_read == 0 do return key != nil;

//     // Process the changes and dispatch those events
//     base    := uintptr(&buffer[0]);
//     current := 0;
//     for {
//         it := cast(^win32.File_Notify_Information)rawptr(base + uintptr(current));

//         path := win32.wstring_to_utf8(cast(win32.Wstring)&it.file_name[0], int(it.file_name_length));

//         switch it.action {
//         case win32.FILE_ACTION_ADDED, win32.FILE_ACTION_RENAMED_NEW_NAME:
//             e : File_Created_Event;

//             e.path = path;

//             core.dispatch_event(&dirmon.dispatcher, &e);
//         case win32.FILE_ACTION_REMOVED, win32.FILE_ACTION_RENAMED_OLD_NAME:
//             e : File_Deleted_Event;

//             e.path = path;

//             core.dispatch_event(&dirmon.dispatcher, &e);
//         case win32.FILE_ACTION_MODIFIED:
//             e : File_Modified_Event;

//             e.path = path;

//             core.dispatch_event(&dirmon.dispatcher, &e);
//         case: unimplemented();
//         }

//         if it.next_entry_offset == 0 do break;
//         current += int(it.next_entry_offset);
//     }

//     return key != nil;
// }

// foreign import "system:kernel32.lib"

// FILE_LIST_DIRECTORY :: 0x1;

// @(default_calling_convention = "std")
// foreign kernel32 {
//     @(link_name="CreateIoCompletionPort") CreateIoCompletionPort :: proc(file_handle                  : windows.HANDLE, 
//                                                                          existing_completion_port     : windows.HANDLE,
//                                                                          completion_key               : ^c.ulong,
//                                                                          number_of_concurrent_threads : u32) -> windows.HANDLE ---;

//     @(link_name="GetQueuedCompletionStatus") GetQueuedCompletionStatus :: proc(completion_port: windows.HANDLE,
//                                                                                number_of_bytes_transferred : ^u32,
//                                                                                completion_key              : ^^c.ulong,
//                                                                                overlapped                  : ^^win32.Overlapped,
//                                                                                milliseconds                : u32) -> bool ---;

//     @(link_name="SetLastError") SetLastError :: proc(error_code : u32) ---;
// }

