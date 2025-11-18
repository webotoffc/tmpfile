#!/bin/bash

###############################################################################
# Pterodactyl Security Modifier Installer v3.1
# Modified by Xyro Official
# Auto-install security modifications to Pterodactyl Panel
# NEW: Admin dapat list server API dan delete server miliknya
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
PANEL_DIR="/var/www/pterodactyl"
BACKUP_DIR="/var/www/pterodactyl-backup-$(date +%Y%m%d-%H%M%S)"
ADMIN_UTAMA_ID="1"
CUSTOM_BRAND="YourPanelName" # Ganti dengan nama panel Anda

# ASCII Art Banner
print_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║   ██████╗ ████████╗███████╗██████╗  ██████╗                 ║
    ║   ██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔═══██╗                ║
    ║   ██████╔╝   ██║   █████╗  ██████╔╝██║   ██║                ║
    ║   ██╔═══╝    ██║   ██╔══╝  ██╔══██╗██║   ██║                ║
    ║   ██║        ██║   ███████╗██║  ██║╚██████╔╝                ║
    ║   ╚═╝        ╚═╝   ╚══════╝╚═╝  ╚═╝ ╚═════╝                 ║
    ║                                                               ║
    ║           Security Modifier Installer v3.1                   ║
    ║              Modified by Xyro Official                      ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    if [ "$1" != "--restore" ] && [ "$1" != "-r" ]; then
        echo -e "${YELLOW}Usage:${NC}"
        echo -e "  ${GREEN}Install:${NC}  bash $0"
        echo -e "  ${GREEN}Restore:${NC}  bash $0 --restore  ${CYAN}(or -r)${NC}"
        echo ""
    fi
}

# Functions
print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_header() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root!"
        exit 1
    fi
}

check_panel_exists() {
    if [ ! -d "$PANEL_DIR" ]; then
        print_error "Pterodactyl Panel tidak ditemukan di $PANEL_DIR"
        exit 1
    fi
    print_success "Pterodactyl Panel ditemukan"
}

get_custom_brand() {
    read -p "$(echo -e ${CYAN}[?]${NC} Masukkan nama panel Anda [default: YourPanelName]: )" brand_input
    if [ ! -z "$brand_input" ]; then
        CUSTOM_BRAND="$brand_input"
    fi
    print_success "Nama panel: $CUSTOM_BRAND"
}

backup_files() {
    print_info "Membuat backup file..."
    mkdir -p "$BACKUP_DIR"
    
    cp -r "$PANEL_DIR/app" "$BACKUP_DIR/" 2>/dev/null || true
    cp -r "$PANEL_DIR/resources" "$BACKUP_DIR/" 2>/dev/null || true
    
    print_success "Backup dibuat di: $BACKUP_DIR"
}

modify_file_controller() {
    print_info "Memodifikasi FileController.php..."
    
    cat > "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/FileController.php" << 'EOFFILE'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Services\Nodes\NodeJWTService;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Transformers\Api\Client\FileObjectTransformer;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CopyFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\PullFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\ListFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\ChmodFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\DeleteFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\RenameFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CreateFolderRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CompressFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\DecompressFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\GetFileContentsRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\WriteFileContentRequest;

class FileController extends ClientApiController
{
    public function __construct(
        private NodeJWTService $jwtService,
        private DaemonFileRepository $fileRepository
    ) {
        parent::__construct();
    }

    public function directory(ListFilesRequest $request, Server $server): array
    {
        $user = auth()->user();
        
        // Prevent non-root admins from browsing files of other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot browse or view the file structure of servers that don't belong to you.");
        }
        
        $contents = $this->fileRepository
            ->setServer($server)
            ->getDirectory($request->get('directory') ?? '/');

        return $this->fractal->collection($contents)
            ->transformWith($this->getTransformer(FileObjectTransformer::class))
            ->toArray();
    }

    public function contents(GetFileContentsRequest $request, Server $server): Response
    {
        $user = auth()->user();
        
        // Prevent non-root admins from viewing files of other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot view or read files from servers that don't belong to you. This server belongs to another user.");
        }
        
        $response = $this->fileRepository->setServer($server)->getContent(
            $request->get('file'),
            config('pterodactyl.files.max_edit_size')
        );

        Activity::event('server:file.read')->property('file', $request->get('file'))->log();

        return new Response($response, Response::HTTP_OK, ['Content-Type' => 'text/plain']);
    }

    public function download(GetFileContentsRequest $request, Server $server): array
    {
        $user = auth()->user();
        
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! This server belongs to another user. You do not have permission to download files from this server.");
        }
        
        $token = $this->jwtService
            ->setExpiresAt(CarbonImmutable::now()->addMinutes(15))
            ->setUser($request->user())
            ->setClaims([
                'file_path' => rawurldecode($request->get('file')),
                'server_uuid' => $server->uuid,
            ])
            ->handle($server->node, $request->user()->id . $server->uuid);

        Activity::event('server:file.download')->property('file', $request->get('file'))->log();

        return [
            'object' => 'signed_url',
            'attributes' => [
                'url' => sprintf(
                    '%s/download/file?token=%s',
                    $server->node->getConnectionAddress(),
                    $token->toString()
                ),
            ],
        ];
    }

    public function write(WriteFileContentRequest $request, Server $server): JsonResponse
    {
        $user = auth()->user();
        
        // Prevent non-root admins from editing files of other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot edit or modify files from servers that don't belong to you.");
        }
        
        $this->fileRepository->setServer($server)->putContent($request->get('file'), $request->getContent());

        Activity::event('server:file.write')->property('file', $request->get('file'))->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function create(CreateFolderRequest $request, Server $server): JsonResponse
    {
        $user = auth()->user();
        
        // Prevent non-root admins from creating folders in other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot create folders in servers that don't belong to you.");
        }
        
        $this->fileRepository
            ->setServer($server)
            ->createDirectory($request->input('name'), $request->input('root', '/'));

        Activity::event('server:file.create-directory')
            ->property('name', $request->input('name'))
            ->property('directory', $request->input('root'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function rename(RenameFileRequest $request, Server $server): JsonResponse
    {
        $user = auth()->user();
        
        // Prevent non-root admins from renaming files in other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot rename files in servers that don't belong to you.");
        }
        
        $this->fileRepository
            ->setServer($server)
            ->renameFiles($request->input('root'), $request->input('files'));

        Activity::event('server:file.rename')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function copy(CopyFileRequest $request, Server $server): JsonResponse
    {
        $user = auth()->user();
        
        // Prevent non-root admins from copying files in other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot copy files in servers that don't belong to you.");
        }
        
        $this->fileRepository
            ->setServer($server)
            ->copyFile($request->input('location'));

        Activity::event('server:file.copy')->property('file', $request->input('location'))->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function compress(CompressFilesRequest $request, Server $server): array
    {
        $user = auth()->user();
        
        // Prevent non-root admins from compressing files in other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot compress files in servers that don't belong to you.");
        }
        
        $file = $this->fileRepository->setServer($server)->compressFiles(
            $request->input('root'),
            $request->input('files')
        );

        Activity::event('server:file.compress')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return $this->fractal->item($file)
            ->transformWith($this->getTransformer(FileObjectTransformer::class))
            ->toArray();
    }

    public function decompress(DecompressFilesRequest $request, Server $server): JsonResponse
    {
        set_time_limit(300);
        
        $user = auth()->user();
        
        // Prevent non-root admins from decompressing files in other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot decompress files in servers that don't belong to you.");
        }

        $this->fileRepository->setServer($server)->decompressFile(
            $request->input('root'),
            $request->input('file')
        );

        Activity::event('server:file.decompress')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('file'))
            ->log();

        return new JsonResponse([], JsonResponse::HTTP_NO_CONTENT);
    }

    public function delete(DeleteFileRequest $request, Server $server): JsonResponse
    {
        $user = auth()->user();
        
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! This server belongs to another user. You do not have permission to delete files from this server.");
        }
        
        $this->fileRepository->setServer($server)->deleteFiles(
            $request->input('root'),
            $request->input('files')
        );

        Activity::event('server:file.delete')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function chmod(ChmodFilesRequest $request, Server $server): JsonResponse
    {
        $user = auth()->user();
        
        // Prevent non-root admins from changing file permissions in other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot change file permissions in servers that don't belong to you.");
        }
        
        $this->fileRepository->setServer($server)->chmodFiles(
            $request->input('root'),
            $request->input('files')
        );

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function pull(PullFileRequest $request, Server $server): JsonResponse
    {
        $user = auth()->user();
        
        // Prevent non-root admins from pulling files to other users' servers
        if ($user->root_admin !== 1 && (int) $server->owner_id !== (int) $user->id) {
            abort(403, "Access Denied! You cannot pull/upload files to servers that don't belong to you.");
        }
        
        $this->fileRepository->setServer($server)->pull(
            $request->input('url'),
            $request->input('directory'),
            $request->safe(['filename', 'use_header', 'foreground'])
        );

        Activity::event('server:file.pull')
            ->property('directory', $request->input('directory'))
            ->property('url', $request->input('url'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }
}
EOFFILE

    print_success "FileController.php dimodifikasi"
}

modify_server_controller() {
    print_info "Memodifikasi ServerController.php (Application API) - Admin bisa list & delete server miliknya..."
    
    cat > "$PANEL_DIR/app/Http/Controllers/Api/Application/Servers/ServerController.php" << 'EOFSERVER'
<?php

namespace Pterodactyl\Http\Controllers\Api\Application\Servers;

use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\User;
use Illuminate\Http\JsonResponse;
use Spatie\QueryBuilder\QueryBuilder;
use Pterodactyl\Services\Servers\ServerCreationService;
use Pterodactyl\Services\Servers\ServerDeletionService;
use Pterodactyl\Transformers\Api\Application\ServerTransformer;
use Pterodactyl\Http\Requests\Api\Application\Servers\GetServerRequest;
use Pterodactyl\Http\Requests\Api\Application\Servers\GetServersRequest;
use Pterodactyl\Http\Requests\Api\Application\Servers\ServerWriteRequest;
use Pterodactyl\Http\Requests\Api\Application\Servers\StoreServerRequest;
use Pterodactyl\Http\Controllers\Api\Application\ApplicationApiController;

class ServerController extends ApplicationApiController
{
    private array $adminUtamaIds = [1];

    public function __construct(
        private ServerCreationService $creationService,
        private ServerDeletionService $deletionService
    ) {
        parent::__construct();
    }

    private function currentUser(): ?User
    {
        $key = $this->request->attributes->get('api_key');
        if ($key && $key->user_id) {
            return User::find($key->user_id);
        }
        return auth()->user();
    }

    private function isAdminUtama(?User $user): bool
    {
        return $user && in_array($user->id, $this->adminUtamaIds);
    }

    public function index(GetServersRequest $request): array|JsonResponse
    {
        $user = $this->currentUser();
        
        // Admin utama bisa lihat semua server
        if ($this->isAdminUtama($user)) {
            $servers = QueryBuilder::for(Server::query())
                ->allowedFilters(['uuid', 'uuidShort', 'name', 'description', 'image', 'external_id'])
                ->allowedSorts(['id', 'uuid'])
                ->paginate($request->query('per_page') ?? 50);
        } 
        // Admin biasa hanya bisa lihat server miliknya sendiri
        elseif ($user && $user->root_admin == 1) {
            $servers = QueryBuilder::for(
                Server::query()->where('owner_id', $user->id)
            )
                ->allowedFilters(['uuid', 'uuidShort', 'name', 'description', 'image', 'external_id'])
                ->allowedSorts(['id', 'uuid'])
                ->paginate($request->query('per_page') ?? 50);
        }
        // Bukan admin sama sekali
        else {
            return response()->json([
                'error' => 'Access Denied',
                'message' => 'Only administrators are allowed to access this resource.'
            ], 403);
        }

        return $this->fractal->collection($servers)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->toArray();
    }

    public function view(GetServerRequest $request, Server $server): array|JsonResponse
    {
        $user = $this->currentUser();
        
        // Admin utama bisa lihat semua server
        if ($this->isAdminUtama($user)) {
            return $this->fractal->item($server)
                ->transformWith($this->getTransformer(ServerTransformer::class))
                ->toArray();
        }
        
        // Admin biasa hanya bisa lihat server miliknya
        if ($user && $user->root_admin == 1 && (int) $server->owner_id === (int) $user->id) {
            return $this->fractal->item($server)
                ->transformWith($this->getTransformer(ServerTransformer::class))
                ->toArray();
        }
        
        return response()->json([
            'error' => 'Access Denied',
            'message' => 'You can only view servers that belong to you.'
        ], 403);
    }

    public function delete(ServerWriteRequest $request, Server $server, string $force = ''): Response|JsonResponse
    {
        $user = $this->currentUser();
        
        // Admin utama bisa hapus semua server
        if ($this->isAdminUtama($user)) {
            $this->deletionService->withForce($force === 'force')->handle($server);
            return $this->returnNoContent();
        }
        
        // Admin biasa hanya bisa hapus server miliknya sendiri
        if ($user && $user->root_admin == 1 && (int) $server->owner_id === (int) $user->id) {
            $this->deletionService->withForce($force === 'force')->handle($server);
            return $this->returnNoContent();
        }
        
        return response()->json([
            'error' => 'Access Denied',
            'message' => 'You can only delete servers that belong to you.'
        ], 403);
    }

    public function store(StoreServerRequest $request): JsonResponse
    {
        $user = $this->currentUser();
        if (!$this->isAdminUtama($user)) {
            return response()->json([
                'error' => 'Access Denied',
                'message' => 'Only main administrators can create servers.'
            ], 403);
        }

        $server = $this->creationService->handle($request->validated(), $request->getDeploymentObject());

        return $this->fractal->item($server)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->respond(201);
    }
}
EOFSERVER

    print_success "ServerController.php (Application API) dimodifikasi - Admin bisa list & delete server miliknya"
}

modify_user_controller() {
    print_info "Memodifikasi UserController.php..."
    
    cat > "$PANEL_DIR/app/Http/Controllers/Api/Application/Users/UserController.php" << 'EOFUSER'
<?php

namespace Pterodactyl\Http\Controllers\Api\Application\Users;

use Pterodactyl\Models\User;
use Illuminate\Http\JsonResponse;
use Spatie\QueryBuilder\QueryBuilder;
use Pterodactyl\Services\Users\UserUpdateService;
use Pterodactyl\Services\Users\UserCreationService;
use Pterodactyl\Services\Users\UserDeletionService;
use Pterodactyl\Transformers\Api\Application\UserTransformer;
use Pterodactyl\Http\Requests\Api\Application\Users\GetUsersRequest;
use Pterodactyl\Http\Requests\Api\Application\Users\StoreUserRequest;
use Pterodactyl\Http\Requests\Api\Application\Users\DeleteUserRequest;
use Pterodactyl\Http\Requests\Api\Application\Users\UpdateUserRequest;
use Pterodactyl\Http\Controllers\Api\Application\ApplicationApiController;

class UserController extends ApplicationApiController
{
    public function __construct(
        private UserCreationService $creationService,
        private UserDeletionService $deletionService,
        private UserUpdateService $updateService
    ) {
        parent::__construct();
    }

    public function index(GetUsersRequest $request): array
    {
        $users = QueryBuilder::for(User::query())
            ->allowedFilters(['email', 'uuid', 'username', 'external_id'])
            ->allowedSorts(['id', 'uuid'])
            ->paginate($request->query('per_page') ?? 50);

        return $this->fractal->collection($users)
            ->transformWith($this->getTransformer(UserTransformer::class))
            ->toArray();
    }

    public function view(GetUsersRequest $request, User $user): array
    {
        return $this->fractal->item($user)
            ->transformWith($this->getTransformer(UserTransformer::class))
            ->toArray();
    }

    public function update(UpdateUserRequest $request, User $user): array
    {
        $this->updateService->setUserLevel(User::USER_LEVEL_ADMIN);
        $user = $this->updateService->handle($user, $request->validated());

        $response = $this->fractal->item($user)
            ->transformWith($this->getTransformer(UserTransformer::class));

        return $response->toArray();
    }

    public function store(StoreUserRequest $request): JsonResponse
    {
        $requestUser = $request->user();

        if ($requestUser && $requestUser->id !== 1 && $request->input('root_admin') == 1) {
            return response()->json([
                'error' => 'Access Denied',
                'message' => 'You are not authorized to create administrator accounts.'
            ], 403);
        }

        if (!$requestUser && $request->input('root_admin') == 1) {
            return response()->json([
                'error' => 'Access Denied',
                'message' => 'This API key is not authorized to create administrator accounts.'
            ], 403);
        }

        $user = $this->creationService->handle($request->validated());

        return $this->fractal->item($user)
            ->transformWith($this->getTransformer(UserTransformer::class))
            ->addMeta([
                'resource' => route('api.application.users.view', [
                    'user' => $user->id,
                ]),
            ])
            ->respond(201);
    }

    public function delete(DeleteUserRequest $request, User $user): JsonResponse
    {
        $this->deletionService->handle($user);

        return new JsonResponse([], JsonResponse::HTTP_NO_CONTENT);
    }
}
EOFUSER

    print_success "UserController.php dimodifikasi"
}

create_access_denied_blade() {
    print_info "Membuat blade template access denied..."
    
    local blade_dir="$PANEL_DIR/resources/views/errors"
    mkdir -p "$blade_dir"
    
    cat > "$blade_dir/access_denied.blade.php" << EOFBLADE
@extends('layouts.admin')

@section('title')
    Access Denied
@endsection

@section('content-header')
    <h1>Access Denied<small>You do not have permission to access this page</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li class="active">Access Denied</li>
    </ol>
@endsection

@section('content')
<div class="row">
    <div class="col-md-12">
        <div class="box box-danger">
            <div class="box-header with-border">
                <h3 class="box-title"><i class="fa fa-exclamation-triangle"></i> Access Denied</h3>
            </div>
            <div class="box-body">
                <div class="alert alert-danger">
                    <h4><i class="fa fa-ban"></i> Permission Denied!</h4>
                    <p>You do not have sufficient permissions to access this page.</p>
                    <p>This page is restricted to <strong>Main Administrators</strong> only.</p>
                    <hr>
                    <p class="mb-0">
                        <small>
                            <i class="fa fa-info-circle"></i> 
                            If you believe this is an error, please contact your system administrator.
                        </small>
                    </p>
                </div>
                
                <div class="callout callout-info">
                    <h4><i class="fa fa-info"></i> Security Notice</h4>
                    <p>This restriction is in place to protect sensitive system settings and prevent unauthorized modifications.</p>
                </div>
            </div>
            <div class="box-footer">
                <a href="{{ route('admin.index') }}" class="btn btn-primary">
                    <i class="fa fa-home"></i> Return to Dashboard
                </a>
            </div>
        </div>
    </div>
</div>
@endsection

@section('footer-scripts')
@parent
<script>
    // Auto redirect after 5 seconds
    setTimeout(function() {
        window.location.href = "{{ route('admin.index') }}";
    }, 5000);
    
    // Show countdown
    var countdown = 5;
    var countdownInterval = setInterval(function() {
        countdown--;
        if (countdown <= 0) {
            clearInterval(countdownInterval);
        }
    }, 1000);
</script>
@endsection
EOFBLADE

    print_success "Access denied blade template dibuat"
}

add_middleware_check() {
    print_info "Menambahkan middleware check untuk admin pages..."
    
    # Buat middleware baru
    local middleware_dir="$PANEL_DIR/app/Http/Middleware"
    mkdir -p "$middleware_dir"
    
    cat > "$middleware_dir/CheckMainAdmin.php" << 'EOFMIDDLEWARE'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class CheckMainAdmin
{
    private array $mainAdminIds = [1];

    public function handle(Request $request, Closure $next)
    {
        $user = $request->user();
        
        if (!$user || !in_array($user->id, $this->mainAdminIds)) {
            if ($request->expectsJson()) {
                return response()->json([
                    'error' => 'Access Denied',
                    'message' => 'Only main administrators can access this resource.'
                ], 403);
            }
            
            return redirect()->route('admin.index')
                ->with('error', 'Access Denied: This page is restricted to main administrators only.');
        }

        return $next($request);
    }
}
EOFMIDDLEWARE

    print_success "Middleware CheckMainAdmin dibuat"
}

modify_admin_views_with_redirect() {
    print_info "Memodifikasi admin views dengan popup access denied..."
    
    # Daftar view yang perlu diproteksi (TIDAK TERMASUK delete.blade.php)
    local views=(
        "$PANEL_DIR/resources/views/admin/settings/mail.blade.php"
        "$PANEL_DIR/resources/views/admin/settings/advanced.blade.php"
        "$PANEL_DIR/resources/views/admin/settings/index.blade.php"
        "$PANEL_DIR/resources/views/admin/nodes/view/settings.blade.php"
        "$PANEL_DIR/resources/views/admin/nodes/view/configuration.blade.php"
        "$PANEL_DIR/resources/views/admin/nodes/view/allocation.blade.php"
        "$PANEL_DIR/resources/views/admin/nodes/index.blade.php"
    )
    
    for view_file in "${views[@]}"; do
        if [ -f "$view_file" ]; then
            # Check if already modified
            if grep -q "adminUtamaIds" "$view_file"; then
                print_info "$(basename $view_file) sudah dimodifikasi, skip..."
                continue
            fi
            
            # Backup original
            cp "$view_file" "${view_file}.bak"
            
            # Add security check at the beginning after @extends
            local temp_file="${view_file}.tmp"
            local found_extends=false
            
            while IFS= read -r line; do
                echo "$line" >> "$temp_file"
                
                # Insert security check after @extends line
                if [[ "$line" =~ ^@extends && "$found_extends" == "false" ]]; then
                    found_extends=true
                    cat >> "$temp_file" << 'EOFSEC'

@php
    $adminUtamaIds = [1];
    $isMainAdmin = in_array(auth()->user()->id, $adminUtamaIds);
@endphp

@if(!$isMainAdmin)
    @section('content')
    <div class="access-denied-overlay" id="accessDeniedOverlay">
        <div class="access-denied-modal">
            <div class="access-denied-header">
                <i class="fa fa-shield" style="font-size: 48px; color: #e74c3c; margin-bottom: 20px;"></i>
                <h2 style="color: #e74c3c; margin: 0;">Access Denied</h2>
            </div>
            <div class="access-denied-body">
                <p style="font-size: 16px; color: #555; margin: 15px 0;">
                    <strong>You do not have permission to access this page.</strong>
                </p>
                <p style="color: #777; margin: 10px 0;">
                    This section is restricted to <strong>Main Administrators</strong> only.
                </p>
                <div style="background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0;">
                    <p style="margin: 5px 0; color: #666;">
                        <i class="fa fa-info-circle"></i> 
                        <strong>Security Notice:</strong>
                    </p>
                    <p style="margin: 5px 0; color: #666; font-size: 14px;">
                        This restriction protects sensitive system configurations.
                    </p>
                </div>
                <div style="margin-top: 25px;">
                    <span id="countdown" style="color: #e74c3c; font-weight: bold;">5</span>
                    <span style="color: #666;"> seconds until redirect...</span>
                </div>
            </div>
            <div class="access-denied-footer">
                <a href="{{ route('admin.index') }}" class="btn btn-danger btn-lg" id="returnBtn">
                    <i class="fa fa-home"></i> Return to Dashboard Now
                </a>
            </div>
        </div>
    </div>

    <style>
        .access-denied-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.85);
            z-index: 999999;
            display: flex;
            justify-content: center;
            align-items: center;
            animation: fadeIn 0.3s ease-in;
        }

        @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
        }

        @keyframes slideDown {
            from {
                transform: translateY(-50px);
                opacity: 0;
            }
            to {
                transform: translateY(0);
                opacity: 1;
            }
        }

        .access-denied-modal {
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
            max-width: 500px;
            width: 90%;
            animation: slideDown 0.4s ease-out;
            overflow: hidden;
        }

        .access-denied-header {
            background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
            padding: 30px;
            text-align: center;
            color: white;
        }

        .access-denied-header h2 {
            color: white !important;
            font-size: 28px;
            font-weight: bold;
        }

        .access-denied-body {
            padding: 30px;
            text-align: center;
        }

        .access-denied-footer {
            padding: 20px 30px 30px;
            text-align: center;
        }

        .access-denied-footer .btn {
            padding: 12px 30px;
            font-size: 16px;
            border-radius: 5px;
            transition: all 0.3s ease;
        }

        .access-denied-footer .btn:hover {
            transform: scale(1.05);
            box-shadow: 0 5px 15px rgba(231, 76, 60, 0.4);
        }

        #countdown {
            font-size: 24px;
        }

        body {
            overflow: hidden;
        }
    </style>

    <script>
        document.addEventListener('DOMContentLoaded', function() {
            let countdown = 5;
            const countdownEl = document.getElementById('countdown');
            const returnBtn = document.getElementById('returnBtn');
            
            const interval = setInterval(function() {
                countdown--;
                if (countdownEl) {
                    countdownEl.textContent = countdown;
                }
                
                if (countdown <= 0) {
                    clearInterval(interval);
                    window.location.href = "{{ route('admin.index') }}";
                }
            }, 1000);

            if (returnBtn) {
                returnBtn.addEventListener('click', function() {
                    clearInterval(interval);
                });
            }

            // Prevent back button
            history.pushState(null, null, location.href);
            window.onpopstate = function() {
                history.go(1);
            };
        });
    </script>
    @endsection
@endif
EOFSEC
                fi
            done < "$view_file"
            
            mv "$temp_file" "$view_file"
            print_success "$(basename $view_file) dimodifikasi dengan popup"
        fi
    done
}

modify_server_delete_view() {
    print_info "Memodifikasi server delete view dengan proteksi owner-based..."
    
    local delete_view="$PANEL_DIR/resources/views/admin/servers/view/delete.blade.php"
    
    if [ -f "$delete_view" ]; then
        # Check if already modified
        if grep -q "canDeleteServer" "$delete_view"; then
            print_info "delete.blade.php sudah dimodifikasi, skip..."
            return
        fi
        
        # Backup original
        cp "$delete_view" "${delete_view}.bak"
        
        # Add security check at the beginning after @extends
        local temp_file="${delete_view}.tmp"
        local found_extends=false
        
        while IFS= read -r line; do
            echo "$line" >> "$temp_file"
            
            # Insert security check after @extends line
            if [[ "$line" =~ ^@extends && "$found_extends" == "false" ]]; then
                found_extends=true
                cat >> "$temp_file" << 'EOFDELETE'

@php
    $adminUtamaIds = [1];
    $currentUser = auth()->user();
    $isMainAdmin = in_array($currentUser->id, $adminUtamaIds);
    $isOwner = (int) $server->owner_id === (int) $currentUser->id;
    $canDeleteServer = $isMainAdmin || $isOwner;
@endphp

@if(!$canDeleteServer)
    @section('content')
    <div class="access-denied-overlay" id="accessDeniedOverlay">
        <div class="access-denied-modal">
            <div class="access-denied-header">
                <i class="fa fa-ban" style="font-size: 48px; color: #e74c3c; margin-bottom: 20px;"></i>
                <h2 style="color: #e74c3c; margin: 0;">Cannot Delete Server</h2>
            </div>
            <div class="access-denied-body">
                <p style="font-size: 16px; color: #555; margin: 15px 0;">
                    <strong>You do not have permission to delete this server.</strong>
                </p>
                <p style="color: #777; margin: 10px 0;">
                    This server belongs to another user.
                </p>
                <div style="background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0;">
                    <p style="margin: 5px 0; color: #666;">
                        <i class="fa fa-info-circle"></i> 
                        <strong>Server Information:</strong>
                    </p>
                    <p style="margin: 5px 0; color: #666; font-size: 14px;">
                        Server Name: <strong>{{ $server->name }}</strong><br>
                        Owner ID: <strong>{{ $server->owner_id }}</strong><br>
                        Your ID: <strong>{{ $currentUser->id }}</strong>
                    </p>
                    <p style="margin: 10px 0 5px 0; color: #e74c3c; font-size: 13px;">
                        <i class="fa fa-exclamation-triangle"></i> 
                        You can only delete servers that you own.
                    </p>
                </div>
                <div style="margin-top: 25px;">
                    <span id="countdown" style="color: #e74c3c; font-weight: bold;">5</span>
                    <span style="color: #666;"> seconds until redirect...</span>
                </div>
            </div>
            <div class="access-denied-footer">
                <a href="{{ route('admin.servers.view', $server->id) }}" class="btn btn-primary btn-lg" id="returnBtn">
                    <i class="fa fa-arrow-left"></i> Back to Server
                </a>
            </div>
        </div>
    </div>

    <style>
        .access-denied-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.85);
            z-index: 999999;
            display: flex;
            justify-content: center;
            align-items: center;
            animation: fadeIn 0.3s ease-in;
        }

        @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
        }

        @keyframes slideDown {
            from {
                transform: translateY(-50px);
                opacity: 0;
            }
            to {
                transform: translateY(0);
                opacity: 1;
            }
        }

        .access-denied-modal {
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
            max-width: 550px;
            width: 90%;
            animation: slideDown 0.4s ease-out;
            overflow: hidden;
        }

        .access-denied-header {
            background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
            padding: 30px;
            text-align: center;
            color: white;
        }

        .access-denied-header h2 {
            color: white !important;
            font-size: 28px;
            font-weight: bold;
        }

        .access-denied-body {
            padding: 30px;
            text-align: center;
        }

        .access-denied-footer {
            padding: 20px 30px 30px;
            text-align: center;
        }

        .access-denied-footer .btn {
            padding: 12px 30px;
            font-size: 16px;
            border-radius: 5px;
            transition: all 0.3s ease;
        }

        .access-denied-footer .btn:hover {
            transform: scale(1.05);
            box-shadow: 0 5px 15px rgba(52, 152, 219, 0.4);
        }

        #countdown {
            font-size: 24px;
        }

        body {
            overflow: hidden;
        }
    </style>

    <script>
        document.addEventListener('DOMContentLoaded', function() {
            let countdown = 5;
            const countdownEl = document.getElementById('countdown');
            const returnBtn = document.getElementById('returnBtn');
            
            const interval = setInterval(function() {
                countdown--;
                if (countdownEl) {
                    countdownEl.textContent = countdown;
                }
                
                if (countdown <= 0) {
                    clearInterval(interval);
                    window.location.href = "{{ route('admin.servers.view', $server->id) }}";
                }
            }, 1000);

            if (returnBtn) {
                returnBtn.addEventListener('click', function() {
                    clearInterval(interval);
                });
            }

            // Prevent back button
            history.pushState(null, null, location.href);
            window.onpopstate = function() {
                history.go(1);
            };
        });
    </script>
    @endsection
@endif
EOFDELETE
            fi
        done < "$delete_view"
        
        mv "$temp_file" "$delete_view"
        print_success "delete.blade.php dimodifikasi dengan proteksi owner-based"
    fi
}

modify_user_views() {
    print_info "Memodifikasi user management views..."
    
    # User edit view
    local user_view="$PANEL_DIR/resources/views/admin/users/view.blade.php"
    if [ -f "$user_view" ] && ! grep -q "@if(auth()->user()->id !== 1) disabled @endif" "$user_view"; then
        sed -i 's/<input type="email" name="email"/<input type="email" name="email" @if(auth()->user()->id !== 1) disabled @endif/g' "$user_view"
        sed -i 's/<input type="text" name="username"/<input type="text" name="username" @if(auth()->user()->id !== 1) disabled @endif/g' "$user_view"
        sed -i 's/<input type="password" id="password"/<input type="password" id="password" @if(auth()->user()->id !== 1) disabled @endif/g' "$user_view"
        sed -i 's/<select name="root_admin" class="form-control">/<select name="root_admin" class="form-control" @if(auth()->user()->id !== 1) disabled @endif>/g' "$user_view"
        sed -i 's/<input id="delete" type="submit"/<input id="delete" type="submit" @if(auth()->user()->id !== 1) disabled @endif/g' "$user_view"
        
        print_success "User view dimodifikasi"
    fi
    
    # User create view
    local user_create="$PANEL_DIR/resources/views/admin/users/new.blade.php"
    if [ -f "$user_create" ] && ! grep -q "@if(auth()->user()->id !== 1) disabled @endif" "$user_create"; then
        sed -i 's/<select name="root_admin" class="form-control">/<select name="root_admin" class="form-control" @if(auth()->user()->id !== 1) disabled @endif>/g' "$user_create"
        sed -i '/<select name="root_admin"/a\                            @if(auth()->user()->id !== 1)\n                                <input type="hidden" name="root_admin" value="0">\n                            @endif' "$user_create"
        
        print_success "User create view dimodifikasi"
    fi
}

clear_cache() {
    print_info "Membersihkan cache..."
    
    cd "$PANEL_DIR"
    php artisan cache:clear > /dev/null 2>&1
    php artisan config:clear > /dev/null 2>&1
    php artisan view:clear > /dev/null 2>&1
    php artisan route:clear > /dev/null 2>&1
    
    print_success "Cache dibersihkan"
}

set_permissions() {
    print_info "Mengatur permissions..."
    
    chown -R www-data:www-data "$PANEL_DIR/app"
    chown -R www-data:www-data "$PANEL_DIR/resources"
    chmod -R 755 "$PANEL_DIR/app"
    chmod -R 755 "$PANEL_DIR/resources"
    
    print_success "Permissions diatur"
}

restart_services() {
    print_info "Restarting services..."
    
    # Restart queue worker
    if systemctl is-active --quiet pteroq; then
        systemctl restart pteroq
        print_success "Queue worker restarted"
    fi
    
    # Restart PHP-FPM
    for version in 8.1 8.2 8.3; do
        if systemctl is-active --quiet php${version}-fpm; then
            systemctl restart php${version}-fpm
            print_success "PHP ${version}-FPM restarted"
            break
        fi
    done
    
    # Restart Nginx
    if systemctl is-active --quiet nginx; then
        systemctl restart nginx
        print_success "Nginx restarted"
    fi
}

verify_installation() {
    print_info "Memverifikasi instalasi..."
    
    local errors=0
    local warnings=0
    
    # Check modified controllers
    if [ ! -f "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/FileController.php" ]; then
        print_error "FileController.php tidak ditemukan"
        ((errors++))
    else
        if grep -q "Access Denied" "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/FileController.php"; then
            print_success "FileController.php terverifikasi"
        else
            print_warning "FileController.php mungkin tidak lengkap"
            ((warnings++))
        fi
    fi
    
    if [ ! -f "$PANEL_DIR/app/Http/Controllers/Api/Application/Servers/ServerController.php" ]; then
        print_error "ServerController.php tidak ditemukan"
        ((errors++))
    else
        print_success "ServerController.php terverifikasi"
    fi
    
    if [ ! -f "$PANEL_DIR/app/Http/Controllers/Api/Application/Users/UserController.php" ]; then
        print_error "UserController.php tidak ditemukan"
        ((errors++))
    else
        print_success "UserController.php terverifikasi"
    fi
    
    # Check middleware
    if [ -f "$PANEL_DIR/app/Http/Middleware/CheckMainAdmin.php" ]; then
        print_success "Middleware CheckMainAdmin terverifikasi"
    else
        print_warning "Middleware CheckMainAdmin tidak ditemukan"
        ((warnings++))
    fi
    
    # Check views
    local view_count=0
    for view in "$PANEL_DIR/resources/views/admin/settings/mail.blade.php" \
                "$PANEL_DIR/resources/views/admin/nodes/view/settings.blade.php"; do
        if [ -f "$view" ] && grep -q "adminUtamaIds" "$view"; then
            ((view_count++))
        fi
    done
    
    if [ $view_count -gt 0 ]; then
        print_success "$view_count protected view files terverifikasi"
    fi
    
    # Check server delete view
    if [ -f "$PANEL_DIR/resources/views/admin/servers/view/delete.blade.php" ]; then
        if grep -q "canDeleteServer" "$PANEL_DIR/resources/views/admin/servers/view/delete.blade.php"; then
            print_success "Server delete view dengan owner-based protection terverifikasi"
        else
            print_warning "Server delete view belum dimodifikasi"
            ((warnings++))
        fi
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        print_success "✓ Verifikasi berhasil! ($warnings warning)"
        return 0
    else
        print_error "✗ Ditemukan $errors error(s) dan $warnings warning(s)"
        return 1
    fi
}

show_summary() {
    echo ""
    print_header "INSTALASI SELESAI"
    
    cat << EOF
${GREEN}╔═══════════════════════════════════════════════════════════════╗
║                    INSTALLATION COMPLETE                      ║
╚═══════════════════════════════════════════════════════════════╝${NC}

${CYAN}📦 Backup Information:${NC}
   Location: ${YELLOW}$BACKUP_DIR${NC}
   
${CYAN}🔒 Security Modifications Applied:${NC}
   ${GREEN}✓${NC} File browse/list: Root admin & server owner only
   ${GREEN}✓${NC} File view/read: Root admin & server owner only  
   ${GREEN}✓${NC} File edit/write: Root admin & server owner only
   ${GREEN}✓${NC} File download: Root admin & server owner only
   ${GREEN}✓${NC} File delete: Root admin & server owner only
   ${GREEN}✓${NC} File operations (copy/rename/compress): Owner only
   ${GREEN}✓${NC} File permissions (chmod): Owner only
   ${GREEN}✓${NC} File upload/pull: Owner only
   ${GREEN}✓${NC} Server API list: Main admin sees all, regular admin sees own
   ${GREEN}✓${NC} Server API delete: Main admin deletes all, regular admin deletes own
   ${GREEN}✓${NC} Server API create: Main admin only (ID: $ADMIN_UTAMA_ID)
   ${GREEN}✓${NC} Server Panel delete: Admin can delete their own servers
   ${GREEN}✓${NC} User creation: Cannot create admin accounts (except root)
   ${GREEN}✓${NC} Admin views: Auto-redirect to dashboard for non-admins
   ${GREEN}✓${NC} Custom error messages: Professional access denied alerts
   
${CYAN}🎯 Protected File Operations:${NC}
   • directory()   - Browse/list files
   • contents()    - View/read file content
   • write()       - Edit/modify files
   • download()    - Download files
   • delete()      - Delete files/folders
   • copy()        - Copy files
   • rename()      - Rename files/folders
   • compress()    - Create archives
   • decompress()  - Extract archives
   • chmod()       - Change permissions
   • pull()        - Upload from URL

${CYAN}🆕 NEW - Admin API Access:${NC}
   ${GREEN}Main Admin (ID: $ADMIN_UTAMA_ID):${NC}
     • GET /api/application/servers - List ALL servers
     • DELETE /api/application/servers/{id} - Delete ANY server
     • POST /api/application/servers - Create new servers
   
   ${YELLOW}Regular Admin:${NC}
     • GET /api/application/servers - List ONLY their own servers
     • DELETE /api/application/servers/{id} - Delete ONLY their own servers
     • POST /api/application/servers - ❌ Cannot create servers
   
${CYAN}👤 Root Admin ID:${NC} ${GREEN}$ADMIN_UTAMA_ID${NC}
${CYAN}🏷️  Panel Brand:${NC} ${GREEN}$CUSTOM_BRAND${NC}

${YELLOW}⚠️  IMPORTANT - Next Steps:${NC}

${BLUE}1.${NC} Test Panel Access:
   ${CYAN}→${NC} URL: $(grep APP_URL $PANEL_DIR/.env 2>/dev/null | cut -d '=' -f2)
   ${CYAN}→${NC} Login as root admin and test functionality
   
${BLUE}2.${NC} Test API Access dengan Postman/curl:
   ${CYAN}→${NC} GET /api/application/servers (test dengan admin biasa)
   ${CYAN}→${NC} DELETE /api/application/servers/{id} (test dengan server milik sendiri)
   
${BLUE}3.${NC} Monitor Logs:
   ${CYAN}→${NC} tail -f $PANEL_DIR/storage/logs/laravel.log
   
${BLUE}4.${NC} Test Security:
   ${CYAN}→${NC} Try accessing protected pages with non-root admin
   ${CYAN}→${NC} Try creating admin user with regular admin
   ${CYAN}→${NC} Try downloading files from other user's servers
   ${CYAN}→${NC} Try listing all servers via API dengan admin biasa
   ${CYAN}→${NC} Try deleting other user's server via API
   ${CYAN}→${NC} ${GREEN}Try deleting own server via Panel (should work for admin)${NC}
   ${CYAN}→${NC} ${GREEN}Try deleting other's server via Panel (should show popup)${NC}
   
${BLUE}5.${NC} If Issues Occur - Restore Backup:
   ${CYAN}→${NC} EASY WAY: bash $(basename $0) --restore
   ${CYAN}→${NC} MANUAL WAY:
       sudo rm -rf $PANEL_DIR/app $PANEL_DIR/resources
       sudo cp -r $BACKUP_DIR/app $PANEL_DIR/
       sudo cp -r $BACKUP_DIR/resources $PANEL_DIR/
       sudo chown -R www-data:www-data $PANEL_DIR
       cd $PANEL_DIR && php artisan cache:clear

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}🎉 Installation successful! Your panel is now more secure.${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

${PURPLE}Modified by Xyro Official${NC}
${PURPLE}Copyright © 2020 - 2025 - Version 3.1${NC}

EOF
}

show_final_notes() {
    echo ""
    print_header "CATATAN PENTING"
    
    cat << EOF
${YELLOW}📋 Daftar File yang Dimodifikasi:${NC}

${CYAN}Backend Controllers:${NC}
  1. app/Http/Controllers/Api/Client/Servers/FileController.php
  2. app/Http/Controllers/Api/Application/Servers/ServerController.php ${GREEN}(UPDATED)${NC}
  3. app/Http/Controllers/Api/Application/Users/UserController.php
  4. app/Http/Middleware/CheckMainAdmin.php (NEW)

${CYAN}Frontend Views:${NC}
  1. resources/views/admin/settings/mail.blade.php
  2. resources/views/admin/settings/advanced.blade.php
  3. resources/views/admin/settings/index.blade.php
  4. resources/views/admin/nodes/view/settings.blade.php
  5. resources/views/admin/nodes/view/configuration.blade.php
  6. resources/views/admin/nodes/view/allocation.blade.php
  7. resources/views/admin/nodes/index.blade.php
  8. resources/views/admin/servers/view/delete.blade.php ${GREEN}(UPDATED - Owner-based)${NC}
  9. resources/views/admin/users/view.blade.php
 10. resources/views/admin/users/new.blade.php
 11. resources/views/errors/access_denied.blade.php (NEW)

${CYAN}🔐 Akses Control Matrix:${NC}

┌────────────────────────────┬──────────┬─────────────┬────────────┐
│ Action                     │ Root     │ Admin       │ User       │
│                            │ Admin    │ (Non-Root)  │ (Regular)  │
├────────────────────────────┼──────────┼─────────────┼────────────┤
│ Browse own server files    │ ✅       │ ✅          │ ✅         │
│ Browse others' files       │ ✅       │ ❌          │ ❌         │
│ View/Read own files        │ ✅       │ ✅          │ ✅         │
│ View/Read others' files    │ ✅       │ ❌          │ ❌         │
│ Edit own server files      │ ✅       │ ✅          │ ✅         │
│ Edit others' files         │ ✅       │ ❌          │ ❌         │
│ Download own server files  │ ✅       │ ✅          │ ✅         │
│ Download others' files     │ ✅       │ ❌          │ ❌         │
│ Delete own server files    │ ✅       │ ✅          │ ✅         │
│ Delete others' files       │ ✅       │ ❌          │ ❌         │
│ Copy/Rename own files      │ ✅       │ ✅          │ ✅         │
│ Copy/Rename others' files  │ ✅       │ ❌          │ ❌         │
│ Compress/Extract own files │ ✅       │ ✅          │ ✅         │
│ Compress/Extract others    │ ✅       │ ❌          │ ❌         │
│ Chmod own files            │ ✅       │ ✅          │ ✅         │
│ Chmod others' files        │ ✅       │ ❌          │ ❌         │
│ Upload to own server       │ ✅       │ ✅          │ ✅         │
│ Upload to others' server   │ ✅       │ ❌          │ ❌         │
│ List all servers (API)     │ ✅       │ ❌          │ ❌         │
│ List own servers (API)     │ ✅       │ ✅          │ ❌         │
│ View any server (API)      │ ✅       │ ❌          │ ❌         │
│ View own server (API)      │ ✅       │ ✅          │ ❌         │
│ Delete any server (API)    │ ✅       │ ❌          │ ❌         │
│ Delete own server (API)    │ ✅       │ ✅          │ ❌         │
│ Delete own server (Panel)  │ ✅       │ ✅          │ ❌         │
│ Delete other server (Panel)│ ✅       │ ❌          │ ❌         │
│ Create server (API)        │ ✅       │ ❌          │ ❌         │
│ Create regular users       │ ✅       │ ✅          │ ❌         │
│ Create admin users         │ ✅       │ ❌          │ ❌         │
│ Edit mail settings         │ ✅       │ ❌          │ ❌         │
│ Edit node settings         │ ✅       │ ❌          │ ❌         │
│ Access admin panel         │ ✅       │ ✅          │ ❌         │
└────────────────────────────┴──────────┴─────────────┴────────────┘

${CYAN}🆕 Contoh Penggunaan API (Admin Biasa):${NC}

${YELLOW}1. List Server Milik Sendiri:${NC}
   curl -X GET "https://panel.domain.com/api/application/servers" \\
     -H "Authorization: Bearer YOUR_API_KEY" \\
     -H "Accept: application/json"
   
   ${GREEN}Response:${NC} Hanya server dengan owner_id = ID admin tersebut

${YELLOW}2. View Server Milik Sendiri:${NC}
   curl -X GET "https://panel.domain.com/api/application/servers/1" \\
     -H "Authorization: Bearer YOUR_API_KEY" \\
     -H "Accept: application/json"
   
   ${GREEN}Response:${NC} Data server jika owner_id cocok
   ${RED}Error 403:${NC} Jika bukan server milik sendiri

${YELLOW}3. Delete Server Milik Sendiri:${NC}
   curl -X DELETE "https://panel.domain.com/api/application/servers/1" \\
     -H "Authorization: Bearer YOUR_API_KEY" \\
     -H "Accept: application/json"
   
   ${GREEN}Response:${NC} Server dihapus jika owner_id cocok
   ${RED}Error 403:${NC} Jika bukan server milik sendiri

${YELLOW}4. Create Server (GAGAL):${NC}
   curl -X POST "https://panel.domain.com/api/application/servers" \\
     -H "Authorization: Bearer YOUR_API_KEY" \\
     -H "Accept: application/json" \\
     -d '{"name":"test"}'
   
   ${RED}Error 403:${NC} "Only main administrators can create servers"

${CYAN}🚨 Troubleshooting:${NC}

${YELLOW}Ingin Mengembalikan ke Kondisi Awal (Restore):${NC}
  → ${GREEN}CARA MUDAH:${NC} bash installer.sh --restore
  → Script akan menampilkan list backup dan memandu restore
  → Pre-restore backup otomatis dibuat untuk safety

${YELLOW}Error 500 - Internal Server Error:${NC}
  → Check: tail -f $PANEL_DIR/storage/logs/laravel.log
  → Fix: php artisan cache:clear && php artisan config:clear

${YELLOW}Blank Page / White Screen:${NC}
  → Check: systemctl status php*-fpm
  → Restart: systemctl restart php8.1-fpm nginx

${YELLOW}Access Denied Loop:${NC}
  → Verify admin ID: SELECT id,email,root_admin FROM users WHERE root_admin=1;
  → Update script if needed: Change ADMIN_UTAMA_ID in this script

${YELLOW}API Returns Empty Server List (Admin Biasa):${NC}
  → Check owner_id: SELECT id,name,owner_id FROM servers WHERE owner_id=YOUR_ADMIN_ID;
  → Pastikan admin memiliki server dengan owner_id yang sesuai

${YELLOW}Cannot Delete Server via API:${NC}
  → Check ownership: SELECT owner_id FROM servers WHERE id=SERVER_ID;
  → Pastikan server owner_id = admin user id

${GREEN}💡 Tips:${NC}
  • Keep backup folder for at least 7 days
  • Test all admin functions after installation
  • Monitor logs for the first 24 hours
  • Update root admin ID if you change primary admin
  • Test API dengan admin biasa untuk memastikan filtering bekerja
  • Gunakan force delete untuk server yang stuck: DELETE /servers/1/force
  • ${CYAN}Simpan script installer untuk restore cepat jika diperlukan${NC}
  • ${CYAN}Gunakan: bash installer.sh --restore untuk restore otomatis${NC}

${CYAN}📞 Support:${NC}
  • Check Laravel logs first
  • Verify PHP version compatibility (8.1+)
  • Ensure all services are running
  • Review this output for commands
  • Test dengan curl/Postman untuk debugging API

EOF
}

confirm_installation() {
    echo ""
    print_warning "Script ini akan memodifikasi file Pterodactyl Panel Anda."
    print_warning "Backup akan dibuat otomatis sebelum modifikasi."
    echo ""
    
    print_info "Modifikasi yang akan diterapkan:"
    echo "  ${GREEN}•${NC} File download/delete protection"
    echo "  ${GREEN}•${NC} Server API list - Admin bisa lihat server miliknya ${YELLOW}(NEW)${NC}"
    echo "  ${GREEN}•${NC} Server API delete - Admin bisa hapus server miliknya ${YELLOW}(NEW)${NC}"
    echo "  ${GREEN}•${NC} Server API create - Hanya main admin"
    echo "  ${GREEN}•${NC} User creation security"
    echo "  ${GREEN}•${NC} Admin pages auto-redirect"
    echo "  ${GREEN}•${NC} Custom error messages"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Lanjutkan instalasi? [y/N]:${NC} )" -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Instalasi dibatalkan oleh user"
        exit 1
    fi
}

restore_from_backup() {
    print_header "RESTORE FROM BACKUP"
    
    echo ""
    print_info "Mencari backup yang tersedia..."
    
    # List all backup directories
    local backups=($(ls -dt /var/www/pterodactyl-backup-* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_error "Tidak ada backup yang ditemukan!"
        echo ""
        print_info "Backup biasanya tersimpan di: /var/www/pterodactyl-backup-YYYYMMDD-HHMMSS"
        exit 1
    fi
    
    echo ""
    print_success "Ditemukan ${#backups[@]} backup:"
    echo ""
    
    local index=1
    for backup in "${backups[@]}"; do
        local backup_date=$(basename "$backup" | sed 's/pterodactyl-backup-//')
        local backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1)
        echo "  ${CYAN}[$index]${NC} $(basename $backup)"
        echo "      ${YELLOW}→${NC} Date: $backup_date"
        echo "      ${YELLOW}→${NC} Size: $backup_size"
        echo "      ${YELLOW}→${NC} Path: $backup"
        echo ""
        ((index++))
    done
    
    echo ""
    read -p "$(echo -e ${CYAN}Pilih nomor backup yang ingin di-restore [1-${#backups[@]}]:${NC} )" backup_choice
    
    if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#backups[@]} ]; then
        print_error "Pilihan tidak valid!"
        exit 1
    fi
    
    local selected_backup="${backups[$((backup_choice-1))]}"
    
    echo ""
    print_warning "PERHATIAN: Restore akan menimpa file yang sudah dimodifikasi!"
    print_warning "Backup dari: $(basename $selected_backup)"
    echo ""
    read -p "$(echo -e ${RED}Yakin ingin restore? [y/N]:${NC} )" -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Restore dibatalkan"
        exit 1
    fi
    
    print_header "RESTORING FILES"
    
    # Create a backup of current state before restore
    local pre_restore_backup="/var/www/pterodactyl-pre-restore-$(date +%Y%m%d-%H%M%S)"
    print_info "Membuat backup current state ke: $pre_restore_backup"
    mkdir -p "$pre_restore_backup"
    cp -r "$PANEL_DIR/app" "$pre_restore_backup/" 2>/dev/null || true
    cp -r "$PANEL_DIR/resources" "$pre_restore_backup/" 2>/dev/null || true
    print_success "Pre-restore backup dibuat"
    
    # Restore app directory
    if [ -d "$selected_backup/app" ]; then
        print_info "Restoring app directory..."
        rm -rf "$PANEL_DIR/app"
        cp -r "$selected_backup/app" "$PANEL_DIR/"
        print_success "app directory restored"
    else
        print_warning "app directory tidak ditemukan di backup"
    fi
    
    # Restore resources directory
    if [ -d "$selected_backup/resources" ]; then
        print_info "Restoring resources directory..."
        rm -rf "$PANEL_DIR/resources"
        cp -r "$selected_backup/resources" "$PANEL_DIR/"
        print_success "resources directory restored"
    else
        print_warning "resources directory tidak ditemukan di backup"
    fi
    
    # Set permissions
    print_info "Setting permissions..."
    chown -R www-data:www-data "$PANEL_DIR/app" 2>/dev/null || true
    chown -R www-data:www-data "$PANEL_DIR/resources" 2>/dev/null || true
    chmod -R 755 "$PANEL_DIR/app" 2>/dev/null || true
    chmod -R 755 "$PANEL_DIR/resources" 2>/dev/null || true
    print_success "Permissions set"
    
    # Clear cache
    print_info "Clearing cache..."
    cd "$PANEL_DIR"
    php artisan cache:clear > /dev/null 2>&1 || true
    php artisan config:clear > /dev/null 2>&1 || true
    php artisan view:clear > /dev/null 2>&1 || true
    php artisan route:clear > /dev/null 2>&1 || true
    print_success "Cache cleared"
    
    # Restart services
    print_info "Restarting services..."
    
    if systemctl is-active --quiet pteroq; then
        systemctl restart pteroq
        print_success "Queue worker restarted"
    fi
    
    for version in 8.1 8.2 8.3; do
        if systemctl is-active --quiet php${version}-fpm; then
            systemctl restart php${version}-fpm
            print_success "PHP ${version}-FPM restarted"
            break
        fi
    done
    
    if systemctl is-active --quiet nginx; then
        systemctl restart nginx
        print_success "Nginx restarted"
    fi
    
    echo ""
    print_header "RESTORE COMPLETED"
    
    cat << EOF
${GREEN}╔═══════════════════════════════════════════════════════════════╗
║                     RESTORE SUCCESSFUL                        ║
╚═══════════════════════════════════════════════════════════════╝${NC}

${CYAN}📦 Restored from:${NC}
   ${YELLOW}$selected_backup${NC}

${CYAN}💾 Pre-restore backup saved to:${NC}
   ${YELLOW}$pre_restore_backup${NC}
   ${GREEN}→${NC} Jika ada masalah, gunakan backup ini untuk rollback

${CYAN}✅ Actions completed:${NC}
   ${GREEN}✓${NC} Files restored from backup
   ${GREEN}✓${NC} Permissions set correctly
   ${GREEN}✓${NC} Cache cleared
   ${GREEN}✓${NC} Services restarted

${YELLOW}⚠️  Next Steps:${NC}

${BLUE}1.${NC} Test Panel Access:
   ${CYAN}→${NC} Login dan pastikan panel berfungsi normal
   ${CYAN}→${NC} Cek apakah modifikasi sudah tidak ada

${BLUE}2.${NC} Verify Restoration:
   ${CYAN}→${NC} Test file operations
   ${CYAN}→${NC} Test admin panel access
   ${CYAN}→${NC} Test API endpoints

${BLUE}3.${NC} If Issues Occur:
   ${CYAN}→${NC} Check logs: tail -f $PANEL_DIR/storage/logs/laravel.log
   ${CYAN}→${NC} Verify services: systemctl status nginx php-fpm pteroq

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}Panel telah dikembalikan ke kondisi sebelum modifikasi${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

${PURPLE}Modified by Xyro Official${NC}

EOF
}

# Main function
main() {
    print_banner
    
    # Check for restore argument
    if [ "$1" == "--restore" ] || [ "$1" == "-r" ]; then
        check_root
        check_panel_exists
        restore_from_backup
        exit 0
    fi
    
    print_header "PRE-INSTALLATION CHECKS"
    check_root
    check_panel_exists
    
    echo ""
    get_custom_brand
    
    confirm_installation
    
    print_header "STARTING INSTALLATION"
    backup_files
    
    print_header "MODIFYING CONTROLLERS"
    modify_file_controller
    modify_server_controller
    modify_user_controller
    
    print_header "CREATING MIDDLEWARE & VIEWS"
    add_middleware_check
    create_access_denied_blade
    
    print_header "MODIFYING ADMIN VIEWS"
    modify_admin_views_with_redirect
    modify_server_delete_view
    modify_user_views
    
    print_header "FINALIZING INSTALLATION"
    clear_cache
    set_permissions
    restart_services
    
    print_header "VERIFICATION"
    if verify_installation; then
        show_summary
        show_final_notes
    else
        echo ""
        print_error "Verifikasi gagal! Periksa error di atas."
        print_warning "Anda bisa restore backup dari: $BACKUP_DIR"
        exit 1
    fi
}

# Error trap
trap 'print_error "Error pada baris $LINENO. Exit code: $?"; exit 1' ERR

# Run main with arguments
main "$@"

# End message
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Installation completed successfully at $(date)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
