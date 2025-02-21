import {
  ServerInfoResponseDto,
  ServerInfoService,
  ServerPingResponse,
  ServerStatsResponseDto,
  ServerVersionReponseDto,
} from '@app/domain';
import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Authenticated } from '../decorators/authenticated.decorator';

@ApiTags('Server Info')
@Controller('server-info')
export class ServerInfoController {
  constructor(private service: ServerInfoService) {}

  @Get()
  getServerInfo(): Promise<ServerInfoResponseDto> {
    return this.service.getInfo();
  }

  @Get('/ping')
  pingServer(): ServerPingResponse {
    return this.service.ping();
  }

  @Get('/version')
  getServerVersion(): ServerVersionReponseDto {
    return this.service.getVersion();
  }

  @Authenticated({ admin: true })
  @Get('/stats')
  getStats(): Promise<ServerStatsResponseDto> {
    return this.service.getStats();
  }
}
